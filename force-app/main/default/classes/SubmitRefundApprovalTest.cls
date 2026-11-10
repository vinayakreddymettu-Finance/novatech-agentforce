@IsTest
private class SubmitRefundApprovalTest {

    @TestSetup
    static void setup() {
        insert new Inventory_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Refund_Manager_Id__c = String.valueOf(UserInfo.getUserId())
        );
    }

    private static Return_Request__c makeReturn(String ref, Decimal amount) {
        Order o = TestDataFactory.makeOrder(ref, 'Delivered', Date.today().addDays(-3), new List<Decimal>{ amount }, 'Standard');
        Return_Request__c rr = new Return_Request__c(Order__c = o.Id, Reason__c = 'x', Refund_Amount__c = amount, Status__c = 'Requested');
        insert rr;
        return [SELECT Id, Name, Status__c FROM Return_Request__c WHERE Id = :rr.Id];
    }

    private static SubmitRefundApproval.Result submit(String num) {
        SubmitRefundApproval.Request q = new SubmitRefundApproval.Request();
        q.returnRequestNumber = num;
        return SubmitRefundApproval.submitOne(q);
    }

    @IsTest
    static void smallRefundIsAutoApproved() {
        Return_Request__c rr = makeReturn('T-3001', 150);
        SubmitRefundApproval.Result r = submit(rr.Name);
        Assert.isTrue(r.success, r.message);
        Assert.areEqual('Approved', r.decision);
        Assert.areEqual('Approved', [SELECT Status__c FROM Return_Request__c WHERE Id = :rr.Id].Status__c);
        Assert.isNull([SELECT Reviewer__c FROM Refund_Approval__c WHERE Return_Request__c = :rr.Id].Reviewer__c);
    }

    @IsTest
    static void bigRefundGoesToTheManager() {
        Return_Request__c rr = makeReturn('T-3002', 899);
        SubmitRefundApproval.Result r = submit(rr.Name);
        Assert.isTrue(r.success, r.message);
        Assert.areEqual('Pending', r.decision);
        Assert.areEqual('Pending Approval', [SELECT Status__c FROM Return_Request__c WHERE Id = :rr.Id].Status__c);
        Refund_Approval__c ap = [SELECT Decision__c, Reviewer__c FROM Refund_Approval__c WHERE Return_Request__c = :rr.Id];
        Assert.areEqual('Pending', ap.Decision__c);
        Assert.isTrue(ap.Reviewer__c == UserInfo.getUserId(), 'Reviewer must be the configured refund manager');
    }

    @IsTest
    static void exactlyTwoHundredNeedsAManager() {
        Return_Request__c rr = makeReturn('T-3003', 200);
        Assert.areEqual('Pending', submit(rr.Name).decision);
    }

    @IsTest
    static void missingManagerBlocksBigRefunds() {
        delete [SELECT Id FROM Inventory_Config__c];
        Return_Request__c rr = makeReturn('T-3004', 899);
        SubmitRefundApproval.Result r = submit(rr.Name);
        Assert.isFalse(r.success);
        Assert.isTrue(r.message.contains('No refund manager'), r.message);
        Assert.areEqual(0, [SELECT COUNT() FROM Refund_Approval__c]);
        Assert.areEqual('Requested', [SELECT Status__c FROM Return_Request__c WHERE Id = :rr.Id].Status__c);
    }

    @IsTest
    static void secondSubmissionIsRefused() {
        Return_Request__c rr = makeReturn('T-3005', 899);
        Assert.isTrue(submit(rr.Name).success);
        SubmitRefundApproval.Result second = submit(rr.Name);
        Assert.isFalse(second.success);
        Assert.areEqual(1, [SELECT COUNT() FROM Refund_Approval__c]);
    }

    @IsTest
    static void unknownDecidedAndEmptyReturnsAreRefused() {
        Assert.isFalse(submit('RET-9999').success, 'unknown number');
        Assert.isFalse(submit('  ').success, 'blank number');

        Return_Request__c rejected = makeReturn('T-3006', 150);
        rejected.Status__c = 'Rejected';
        update rejected;
        Assert.isFalse(submit(rejected.Name).success, 'already rejected');

        Return_Request__c zero = makeReturn('T-3007', 150);
        zero.Refund_Amount__c = 0;
        update zero;
        Assert.isFalse(submit(zero.Name).success, 'zero amount');
        Assert.areEqual(0, [SELECT COUNT() FROM Refund_Approval__c]);
    }
}