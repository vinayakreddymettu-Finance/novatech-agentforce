public with sharing class GetOrderStatus {

    public class Request {
        @InvocableVariable(label='Order Reference' description='Order reference such as ORD-1045' required=true)
        public String orderReference;
    }

    public class Result {
        @InvocableVariable(label='Order Found' description='True if an order with this reference exists')
        public Boolean found;
        @InvocableVariable(label='Order Reference' description='The order reference that was looked up')
        public String orderReference;
        @InvocableVariable(label='Order Status' description='Fulfillment status of the order, such as Processing, Shipped, In Transit, Delayed, or Delivered')
        public String orderStatus;
        @InvocableVariable(label='Order Date' description='Date the order was placed')
        public Date orderDate;
        @InvocableVariable(label='Order Total' description='Total value of the order in dollars')
        public Decimal orderTotal;
        @InvocableVariable(label='Delivered Date' description='Date the order was delivered, empty if not delivered')
        public Date deliveredDate;
        @InvocableVariable(label='Has Shipment' description='True if a shipment record exists for the order')
        public Boolean hasShipment;
        @InvocableVariable(label='Tracking Number' description='Tracking number of the shipment, empty if none')
        public String trackingNumber;
        @InvocableVariable(label='Shipment Status' description='Status of the shipment, empty if none')
        public String shipmentStatus;
        @InvocableVariable(label='Expected Arrival Date' description='Expected delivery date of the shipment, empty if none')
        public Date eta;
        @InvocableVariable(label='Is Overdue' description='True if the order is delayed or past its expected arrival date and not yet delivered')
        public Boolean isOverdue;
        @InvocableVariable(label='Days Overdue' description='Number of days past the expected arrival date, empty if unknown')
        public Integer daysOverdue;
        @InvocableVariable(label='Message' description='Plain-language summary of the facts found. Report only this information to the customer. If it says the lookup failed, say the lookup failed and never say the order or shipment does not exist.')
        public String message;
    }

    @InvocableMethod(label='Get Order Status' description='Looks up an order by its reference and returns its real status, shipment tracking number, expected arrival date, and whether it is overdue. Use this before answering any question about where an order is. Never invent tracking updates.')
    public static List<Result> getStatus(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(lookupOne(req));
        }
        return results;
    }

    public static Result lookupOne(Request req) {
        try {
            return lookupInternal(req);
        } catch (Exception e) {
            Result r = new Result();
            r.found = false;
            r.hasShipment = false;
            r.isOverdue = false;
            r.orderReference = (req == null || req.orderReference == null) ? '' : req.orderReference.trim();
            r.message = 'The order lookup FAILED (' + e.getTypeName() + '). This does not mean the order or its shipment does not exist. Tell the representative the lookup failed and to try again or contact an administrator. Do not guess.';
            return r;
        }
    }

    private static Result lookupInternal(Request req) {
        Result r = new Result();
        r.found = false;
        r.hasShipment = false;
        r.isOverdue = false;

        String ref = (req == null || req.orderReference == null) ? '' : req.orderReference.trim();
        r.orderReference = ref;
        if (ref == '') {
            r.message = 'No order reference was provided.';
            return r;
        }

        List<Order> orders = [
            SELECT Id, Fulfillment_Status__c, EffectiveDate, Delivered_Date__c, TotalAmount
            FROM Order
            WHERE Order_Reference__c = :ref
            LIMIT 1
        ];
        if (orders.isEmpty()) {
            r.message = 'No order was found with reference ' + ref + '.';
            return r;
        }
        Order o = orders[0];
        r.found = true;
        r.orderStatus = o.Fulfillment_Status__c;
        r.orderDate = o.EffectiveDate;
        r.orderTotal = o.TotalAmount;
        r.deliveredDate = o.Delivered_Date__c;

        List<Shipment__c> ships = [
            SELECT Tracking_Number__c, ETA__c, Status__c
            FROM Shipment__c
            WHERE Order__c = :o.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Date today = Date.today();
        Boolean closed = o.Fulfillment_Status__c == 'Delivered' || o.Fulfillment_Status__c == 'Cancelled';
        Boolean pastEta = false;
        if (!ships.isEmpty()) {
            r.hasShipment = true;
            r.trackingNumber = ships[0].Tracking_Number__c;
            r.shipmentStatus = ships[0].Status__c;
            r.eta = ships[0].ETA__c;
            if (r.eta != null && r.eta < today) {
                pastEta = true;
                r.daysOverdue = r.eta.daysBetween(today);
            }
        }
        r.isOverdue = !closed && (o.Fulfillment_Status__c == 'Delayed' || pastEta);

        String msg = 'Order ' + ref + ' has status "' + o.Fulfillment_Status__c + '".';
        if (o.Fulfillment_Status__c == 'Delivered' && o.Delivered_Date__c != null) {
            msg += ' It was delivered on ' + o.Delivered_Date__c.format() + '.';
        }
        if (r.hasShipment) {
            msg += ' Tracking number ' + r.trackingNumber + ', shipment status "' + r.shipmentStatus + '"';
            msg += (r.eta != null) ? ', expected arrival ' + r.eta.format() + '.' : ', no expected arrival date on file.';
        } else {
            msg += ' There is no shipment record for this order yet.';
        }
        if (r.isOverdue) {
            msg += ' This order is overdue' + (r.daysOverdue != null ? ' by ' + r.daysOverdue + ' day(s).' : '.');
        }
        r.message = msg;
        return r;
    }
}