@IsTest
private class GetOrderStatusTest {

    private static GetOrderStatus.Result lookup(String ref) {
        GetOrderStatus.Request q = new GetOrderStatus.Request();
        q.orderReference = ref;
        return GetOrderStatus.lookupOne(q);
    }

    private static void addShipment(Id orderId, Date eta, String status) {
        insert new Shipment__c(Order__c = orderId, Tracking_Number__c = 'TRK123', ETA__c = eta, Status__c = status);
    }

    @IsTest
    static void delayedShipmentIsOverdue() {
        Order o = TestDataFactory.makeOrder('T-6001', 'Delayed', null, new List<Decimal>{ 80 }, 'Standard');
        addShipment(o.Id, Date.today().addDays(-1), 'Delayed');
        GetOrderStatus.Result r = lookup('T-6001');
        Assert.isTrue(r.found);
        Assert.isTrue(r.hasShipment);
        Assert.isTrue(r.isOverdue);
        Assert.areEqual(1, r.daysOverdue);
        Assert.areEqual('TRK123', r.trackingNumber);
    }

    @IsTest
    static void onTimeShipmentIsNotOverdue() {
        Order o = TestDataFactory.makeOrder('T-6002', 'In Transit', null, new List<Decimal>{ 80 }, 'Standard');
        addShipment(o.Id, Date.today().addDays(2), 'In Transit');
        GetOrderStatus.Result r = lookup('T-6002');
        Assert.isFalse(r.isOverdue);
        Assert.isNull(r.daysOverdue);
    }

    @IsTest
    static void pastEtaCountsAsOverdueEvenIfNotMarkedDelayed() {
        Order o = TestDataFactory.makeOrder('T-6003', 'In Transit', null, new List<Decimal>{ 80 }, 'Standard');
        addShipment(o.Id, Date.today().addDays(-2), 'In Transit');
        GetOrderStatus.Result r = lookup('T-6003');
        Assert.isTrue(r.isOverdue);
        Assert.areEqual(2, r.daysOverdue);
    }

    @IsTest
    static void deliveredOrderIsNeverOverdue() {
        Order o = TestDataFactory.makeOrder('T-6004', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 80 }, 'Standard');
        addShipment(o.Id, Date.today().addDays(-5), 'Delivered');
        GetOrderStatus.Result r = lookup('T-6004');
        Assert.isFalse(r.isOverdue);
        Assert.isTrue(r.message.contains('delivered on'), r.message);
    }

    @IsTest
    static void missingShipmentIsStatedPlainly() {
        TestDataFactory.makeOrder('T-6005', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 80 }, 'Standard');
        GetOrderStatus.Result r = lookup('T-6005');
        Assert.isTrue(r.found);
        Assert.isFalse(r.hasShipment);
        Assert.isTrue(r.message.contains('no shipment record'), r.message);
    }

    @IsTest
    static void unknownBlankAndNullRequestsAreHandled() {
        GetOrderStatus.Result unknown = lookup('T-9999');
        Assert.isFalse(unknown.found);
        Assert.isTrue(unknown.message.contains('No order was found'), unknown.message);
        Assert.isTrue(lookup('  ').message.contains('No order reference'));
        Assert.isFalse(GetOrderStatus.lookupOne(null).found);
    }

    @IsTest
    static void invocableMethodReturnsOneResultPerRequest() {
        TestDataFactory.makeOrder('T-6006', 'Processing', null, new List<Decimal>{ 80 }, 'Standard');
        GetOrderStatus.Request q = new GetOrderStatus.Request();
        q.orderReference = 'T-6006';
        List<GetOrderStatus.Result> out = GetOrderStatus.getStatus(new List<GetOrderStatus.Request>{ q });
        Assert.areEqual(1, out.size());
        Assert.isTrue(out[0].found);
    }
}