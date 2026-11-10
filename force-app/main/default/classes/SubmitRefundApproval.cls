public with sharing class SubmitRefundApproval {

    public static final Decimal APPROVAL_THRESHOLD = 200;

    public class Request {
        @InvocableVariable(label='Return Request Number' description='Return request number such as RET-0012' required=true)
        public String returnRequestNumber;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True if the approval was submitted')
        public Boolean success;
        @InvocableVariable(label='Approval Id' description='Salesforce record id of the approval record')
        public String approvalId;
        @InvocableVariable(label='Approval Number' description='Approval number such as APR-0003')
        public String approvalNumber;
        @InvocableVariable(label='Decision' description='Pending if a manager must decide, or Approved if auto-approved')
        public String decision;
        @InvocableVariable(label='Return Status' description='Current status of the return request')
        public String returnStatus;
        @InvocableVariable(label='Message' description='Plain-language result to tell the customer')
        public String message;
    }

    @InvocableMethod(label='Submit Refund Approval' description='Submits a return request for refund approval. Refunds under 200 dollars are approved automatically; refunds of 200 dollars or more create a pending approval for a manager. Cannot be used to approve or reject a refund directly.')
    public static List<Result> submit(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(submitOne(req));
        }
        return results;
    }

    private static Id findManager() {
        Inventory_Config__c cfg = Inventory_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Refund_Manager_Id__c)) {
            return null;
        }
        List<User> u = [SELECT Id FROM User WHERE Id = :cfg.Refund_Manager_Id__c AND IsActive = true LIMIT 1];
        return u.isEmpty() ? null : u[0].Id;
    }

    public static Result submitOne(Request req) {
        Result r = new Result();
        r.success = false;

        if (req == null || String.isBlank(req.returnRequestNumber)) {
            r.message = 'Approval not submitted. No return request number was provided.';
            return r;
        }
        String num = req.returnRequestNumber.trim();

        List<Return_Request__c> rrs = [
            SELECT Id, Name, Status__c, Refund_Amount__c
            FROM Return_Request__c
            WHERE Name = :num
            LIMIT 1
        ];
        if (rrs.isEmpty()) {
            r.message = 'Approval not submitted. No return request was found with number ' + num + '.';
            return r;
        }
        Return_Request__c rr = rrs[0];
        r.returnStatus = rr.Status__c;

        if (rr.Status__c != 'Requested') {
            r.message = 'Approval not submitted. ' + rr.Name + ' is already in status "' + rr.Status__c + '".';
            return r;
        }

        Integer existing = [SELECT COUNT() FROM Refund_Approval__c WHERE Return_Request__c = :rr.Id];
        if (existing > 0) {
            r.message = 'Approval not submitted. An approval record already exists for ' + rr.Name + '.';
            return r;
        }

        if (rr.Refund_Amount__c == null || rr.Refund_Amount__c <= 0) {
            r.message = 'Approval not submitted. ' + rr.Name + ' has no valid refund amount.';
            return r;
        }

        Boolean needsManager = rr.Refund_Amount__c >= APPROVAL_THRESHOLD;
        Id managerId = null;
        if (needsManager) {
            managerId = findManager();
            if (managerId == null) {
                r.message = 'Approval not submitted. No refund manager is configured, so a manager decision cannot be requested.';
                return r;
            }
        }

        Refund_Approval__c ap = new Refund_Approval__c(
            Return_Request__c = rr.Id,
            Amount__c = rr.Refund_Amount__c
        );
        if (needsManager) {
            ap.Decision__c = 'Pending';
            ap.Reviewer__c = managerId;
            rr.Status__c = 'Pending Approval';
        } else {
            ap.Decision__c = 'Approved';
            rr.Status__c = 'Approved';
        }
        insert ap;
        update rr;
        ap = [SELECT Id, Name, Decision__c FROM Refund_Approval__c WHERE Id = :ap.Id];

        r.success = true;
        r.approvalId = ap.Id;
        r.approvalNumber = ap.Name;
        r.decision = ap.Decision__c;
        r.returnStatus = rr.Status__c;
        r.message = needsManager
            ? rr.Name + ' for $' + rr.Refund_Amount__c + ' needs manager approval. Approval record ' + ap.Name + ' is pending.'
            : rr.Name + ' for $' + rr.Refund_Amount__c + ' was auto-approved (under $' + APPROVAL_THRESHOLD + '). Approval record ' + ap.Name + ' logged.';
        return r;
    }
}