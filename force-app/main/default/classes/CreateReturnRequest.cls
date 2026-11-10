public with sharing class CreateReturnRequest {

    public static final Decimal APPROVAL_THRESHOLD = 200;

    public class Request {
        @InvocableVariable(label='Order Reference' description='Order reference such as ORD-1045' required=true)
        public String orderReference;
        @InvocableVariable(label='Product Code' description='SKU of the item being returned. Leave blank to return the whole order.')
        public String productCode;
        @InvocableVariable(label='Reason' description='Why the customer wants to return the item' required=true)
        public String reason;
        @InvocableVariable(label='Customer Confirmed' description='True only after the customer has explicitly confirmed they want the return request created' required=true)
        public Boolean customerConfirmed;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Return Request Id')
        public String returnRequestId;
        @InvocableVariable(label='Return Request Number')
        public String returnRequestNumber;
        @InvocableVariable(label='Refund Amount')
        public Decimal refundAmount;
        @InvocableVariable(label='Requires Approval')
        public Boolean requiresApproval;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Create Return Request' description='Creates a return request for an eligible order after the customer has explicitly confirmed. Returns the new return request and whether manager approval is needed.')
    public static List<Result> create(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(createOne(req));
        }
        return results;
    }

    public static Result createOne(Request req) {
        Result r = new Result();
        r.success = false;
        r.requiresApproval = false;

        if (req == null || String.isBlank(req.orderReference)) {
            r.message = 'Return not created. No order reference was provided.';
            return r;
        }
        if (req.customerConfirmed != true) {
            r.message = 'Return not created. The customer has not explicitly confirmed the request.';
            return r;
        }
        if (String.isBlank(req.reason)) {
            r.message = 'Return not created. A reason is required.';
            return r;
        }

        String ref = req.orderReference.trim();

        CheckReturnEligibility.Result elig = CheckReturnEligibility.evaluate(ref);
        if (!elig.eligible) {
            r.message = 'Return not created. ' + elig.reason;
            return r;
        }

        Order o = [
            SELECT Id, (SELECT Quantity, UnitPrice, Product2.ProductCode FROM OrderItems)
            FROM Order
            WHERE Order_Reference__c = :ref
            LIMIT 1
        ];

        String code = String.isBlank(req.productCode) ? null : req.productCode.trim();
        Decimal amount = 0;
        Boolean found = false;
        for (OrderItem oi : o.OrderItems) {
            if (code == null || oi.Product2.ProductCode == code) {
                amount += oi.UnitPrice * oi.Quantity;
                found = true;
            }
        }
        if (!found) {
            r.message = 'Return not created. No item with product code ' + code + ' was found on order ' + ref + '.';
            return r;
        }

        Return_Request__c rr = new Return_Request__c(
            Order__c = o.Id,
            Reason__c = req.reason,
            Refund_Amount__c = amount,
            Status__c = 'Requested'
        );
        insert rr;
        rr = [SELECT Id, Name FROM Return_Request__c WHERE Id = :rr.Id];

        r.success = true;
        r.returnRequestId = rr.Id;
        r.returnRequestNumber = rr.Name;
        r.refundAmount = amount;
        r.requiresApproval = amount >= APPROVAL_THRESHOLD;
        r.message = 'Return request ' + rr.Name + ' created for $' + amount + '.'
            + (r.requiresApproval ? ' Manager approval is required.' : ' No manager approval is required.');
        return r;
    }
}