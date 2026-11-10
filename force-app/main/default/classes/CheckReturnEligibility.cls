public with sharing class CheckReturnEligibility {

    private static final Integer RETURN_WINDOW_DAYS = 30;

    public class Request {
        @InvocableVariable(label='Order Reference' description='Order reference such as ORD-1045' required=true)
        public String orderReference;
    }

    public class Result {
        @InvocableVariable(label='Eligible' description='True if the order can be returned')
        public Boolean eligible;
        @InvocableVariable(label='Reason' description='Plain-language explanation of the decision')
        public String reason;
    }

    @InvocableMethod(label='Check Return Eligibility' description='Checks the return policy for an order and returns Eligible or Not Eligible with a reason.')
    public static List<Result> check(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(evaluate(req.orderReference));
        }
        return results;
    }

    public static Result evaluate(String orderReference) {
        Result r = new Result();
        r.eligible = false;

        if (String.isBlank(orderReference)) {
            r.reason = 'No order reference was provided.';
            return r;
        }
        String ref = orderReference.trim();

        List<Order> orders = [
            SELECT Id, Fulfillment_Status__c, Delivered_Date__c
            FROM Order
            WHERE Order_Reference__c = :ref
            LIMIT 1
        ];
        if (orders.isEmpty()) {
            r.reason = 'No order was found with reference ' + ref + '.';
            return r;
        }
        Order o = orders[0];

        if (o.Fulfillment_Status__c != 'Delivered' || o.Delivered_Date__c == null) {
            r.reason = 'This order has not been delivered yet (current status: ' + o.Fulfillment_Status__c + '), so it cannot be returned.';
            return r;
        }

        Integer daysSinceDelivery = o.Delivered_Date__c.daysBetween(Date.today());
        if (daysSinceDelivery > RETURN_WINDOW_DAYS) {
            r.reason = 'This order was delivered ' + daysSinceDelivery + ' days ago, which is outside the ' + RETURN_WINDOW_DAYS + '-day return window.';
            return r;
        }

        Integer activeReturns = [
            SELECT COUNT() FROM Return_Request__c
            WHERE Order__c = :o.Id
            AND Status__c IN ('Requested', 'Pending Approval', 'Approved', 'Completed')
        ];
        if (activeReturns > 0) {
            r.reason = 'A return request already exists for this order.';
            return r;
        }

        r.eligible = true;
        r.reason = 'Eligible: delivered ' + daysSinceDelivery + ' days ago, within the ' + RETURN_WINDOW_DAYS + '-day window, and no existing return request.';
        return r;
    }
}