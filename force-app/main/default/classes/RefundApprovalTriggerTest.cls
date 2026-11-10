@IsTest
private class RefundApprovalTriggerTest {

    private static Refund_Approval__c makePending(String ref, Decimal amount, Id reviewerId) {
        Order o = TestDataFactory.makeOrder(ref, 'Delivered', Date.today().addDays(-3), new List<Decimal>{ amount }, 'Standard');
        Return_Request__c rr = new Return_Request__c(Order__c = o.Id, Reason__c = 'x', Refund_Amount__c = amount, Status__c = 'Pending Approval');
        insert rr;
        Refund_Approval__c ap = new Refund_Approval__c(Return_Request__c = rr.Id, Amount__c = amount, Decision__c = 'Pending', Reviewer__c = reviewerId);
        insert ap;
        return ap;
    }

    private static String returnStatus(Id approvalReturnId) {
        return [SELECT Status__c FROM Return_Request__c WHERE Id = :approvalReturnId].Status__c;
    }

    @IsTest
    static void approvingUpdatesTheReturn() {
        Refund_Approval__c ap = makePending('T-4001', 899, UserInfo.getUserId());
        ap.Decision__c = 'Approved';
        update ap;
        Assert.areEqual('Approved', returnStatus(ap.Return_Request__c));
    }

    @IsTest
    static void rejectingUpdatesTheReturn() {
        Refund_Approval__c ap = makePending('T-4002', 899, UserInfo.getUserId());
        ap.Decision__c = 'Rejected';
        update ap;
        Assert.areEqual('Rejected', returnStatus(ap.Return_Request__c));
    }

    @IsTest
    static void decidedApprovalCannotBeFlipped() {
        Refund_Approval__c ap = makePending('T-4003', 899, UserInfo.getUserId());
        ap.Decision__c = 'Approved';
        update ap;
        ap.Decision__c = 'Rejected';
        Database.SaveResult res = Database.update(ap, false);
        Assert.isFalse(res.isSuccess());
        Assert.isTrue(res.getErrors()[0].getMessage().contains('already been decided'), res.getErrors()[0].getMessage());
        Assert.areEqual('Approved', returnStatus(ap.Return_Request__c));
    }

    @IsTest
    static void amountCannotBeChanged() {
        Refund_Approval__c ap = makePending('T-4004', 899, UserInfo.getUserId());
        ap.Amount__c = 10;
        Database.SaveResult res = Database.update(ap, false);
        Assert.isFalse(res.isSuccess());
        Assert.isTrue(res.getErrors()[0].getMessage().contains('cannot be changed'), res.getErrors()[0].getMessage());
    }

    @IsTest
    static void bigRefundCannotStartApproved() {
        Order o = TestDataFactory.makeOrder('T-4005', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 899 }, 'Standard');
        Return_Request__c rr = new Return_Request__c(Order__c = o.Id, Reason__c = 'x', Refund_Amount__c = 899, Status__c = 'Requested');
        insert rr;
        Refund_Approval__c cheat = new Refund_Approval__c(Return_Request__c = rr.Id, Amount__c = 899, Decision__c = 'Approved');
        Database.SaveResult res = Database.insert(cheat, false);
        Assert.isFalse(res.isSuccess());
        Assert.isTrue(res.getErrors()[0].getMessage().contains('must start as Pending'), res.getErrors()[0].getMessage());
    }

    @IsTest
    static void smallRefundMayStartApproved() {
        Order o = TestDataFactory.makeOrder('T-4006', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 50 }, 'Standard');
        Return_Request__c rr = new Return_Request__c(Order__c = o.Id, Reason__c = 'x', Refund_Amount__c = 50, Status__c = 'Requested');
        insert rr;
        Refund_Approval__c ok = new Refund_Approval__c(Return_Request__c = rr.Id, Amount__c = 50, Decision__c = 'Approved');
        Database.SaveResult res = Database.insert(ok, false);
        Assert.isTrue(res.isSuccess());
    }

    @IsTest
    static void onlyTheAssignedReviewerCanDecide() {
        List<User> others = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1];
        if (others.isEmpty()) {
            return;
        }
        Refund_Approval__c ap = makePending('T-4007', 899, others[0].Id);
        ap.Decision__c = 'Approved';
        Database.SaveResult res = Database.update(ap, false);
        Assert.isFalse(res.isSuccess());
        Assert.isTrue(res.getErrors()[0].getMessage().contains('assigned reviewer'), res.getErrors()[0].getMessage());
    }
}