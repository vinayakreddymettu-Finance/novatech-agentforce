public with sharing class EscalateSupportCase {

    public static final Decimal HIGH_VALUE_THRESHOLD = 500;

    public class Request {
        @InvocableVariable(label='Order Reference' description='Order reference such as ORD-1045' required=true)
        public String orderReference;
        @InvocableVariable(label='Escalation Reason' description='Why this needs a human, in plain language' required=true)
        public String escalationReason;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Created New Case')
        public Boolean created;
        @InvocableVariable(label='Case Id')
        public String caseId;
        @InvocableVariable(label='Case Number')
        public String caseNumber;
        @InvocableVariable(label='Priority')
        public String priority;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Escalate Support Case' description='Opens a support case for an order that needs human attention. Priority is set automatically from order data. If an open case already exists for the order, that case is returned instead of creating a duplicate.')
    public static List<Result> escalate(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(escalateOne(req));
        }
        return results;
    }

    public static Result escalateOne(Request req) {
        Result r = new Result();
        r.success = false;
        r.created = false;

        if (req == null || String.isBlank(req.orderReference)) {
            r.message = 'Case not created. No order reference was provided.';
            return r;
        }
        if (String.isBlank(req.escalationReason)) {
            r.message = 'Case not created. An escalation reason is required.';
            return r;
        }
        String ref = req.orderReference.trim();

        List<Order> orders = [
            SELECT Id, AccountId, CustomerAuthorizedById, TotalAmount, Fulfillment_Status__c, Account.Customer_Tier__c
            FROM Order
            WHERE Order_Reference__c = :ref
            LIMIT 1
        ];
        if (orders.isEmpty()) {
            r.message = 'Case not created. No order was found with reference ' + ref + '.';
            return r;
        }
        Order o = orders[0];

        List<Case> openCases = [
            SELECT Id, CaseNumber, Priority
            FROM Case
            WHERE Order__c = :o.Id AND IsClosed = false
            LIMIT 1
        ];
        if (!openCases.isEmpty()) {
            r.success = true;
            r.caseId = openCases[0].Id;
            r.caseNumber = openCases[0].CaseNumber;
            r.priority = openCases[0].Priority;
            r.message = 'An open case already exists for ' + ref + ': case ' + r.caseNumber + '. No new case was created.';
            return r;
        }

        String tier = o.Account.Customer_Tier__c;
        Boolean high = o.Fulfillment_Status__c == 'Delayed'
            || (o.TotalAmount != null && o.TotalAmount >= HIGH_VALUE_THRESHOLD)
            || tier == 'Gold' || tier == 'Platinum';
        String priority = high ? 'High' : 'Medium';

        Case c = new Case(
            Subject = 'Escalation for order ' + ref,
            Description = req.escalationReason,
            Escalation_Reason__c = req.escalationReason.abbreviate(255),
            Priority = priority,
            Status = 'New',
            AccountId = o.AccountId,
            ContactId = o.CustomerAuthorizedById,
            Order__c = o.Id
        );
        insert c;
        c = [SELECT Id, CaseNumber FROM Case WHERE Id = :c.Id];

        r.success = true;
        r.created = true;
        r.caseId = c.Id;
        r.caseNumber = c.CaseNumber;
        r.priority = priority;
        r.message = 'Case ' + c.CaseNumber + ' created for ' + ref + ' with ' + priority + ' priority.';
        return r;
    }
}