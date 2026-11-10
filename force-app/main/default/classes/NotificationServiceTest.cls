@IsTest
private class NotificationServiceTest {

    // The pretend Google: counts calls and always answers "OK".
    private class FakeGoogle implements HttpCalloutMock {
        public Integer calls = 0;
        public HttpResponse respond(HttpRequest req) {
            calls++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"ok":true,"status":"Sent"}');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        // Fake address and key, so tests can never reach the real script.
        insert new Inventory_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Web_App_URL__c = 'https://example.com/fake/exec',
            API_Key__c = 'test-key-not-real',
            Refund_Manager_Id__c = UserInfo.getUserId()
        );
    }

    @IsTest
    static void firstSendIsSentSecondIsDuplicate() {
        FakeGoogle fake = new FakeGoogle();
        Test.setMock(HttpCalloutMock.class, fake);

        Test.startTest();
        NotificationService.Outcome first = NotificationService.send(
            'TEST-KEY-1', 'Test Event', 'someone@example.com', 'Subject', 'Body');
        NotificationService.Outcome second = NotificationService.send(
            'TEST-KEY-1', 'Test Event', 'someone@example.com', 'Subject', 'Body');
        Test.stopTest();

        Assert.areEqual('Sent', first.status, first.message);
        Assert.areEqual('Duplicate', second.status, second.message);
        Assert.areEqual(1, fake.calls, 'Google must be called only once');
        Assert.areEqual(1, [SELECT COUNT() FROM Notification_Log__c WHERE Notification_Key__c = 'TEST-KEY-1']);
    }

    @IsTest
    static void twoQueuedNotificationsAreBothSent() {
        FakeGoogle fake = new FakeGoogle();
        Test.setMock(HttpCalloutMock.class, fake);

        Test.startTest();
        System.enqueueJob(new NotificationQueueable(new NotificationQueueable.Payload(
            'TEST-KEY-A', 'E', 'a@example.com', 'S', 'B')));
        System.enqueueJob(new NotificationQueueable(new NotificationQueueable.Payload(
            'TEST-KEY-B', 'E', 'a@example.com', 'S', 'B')));
        Test.stopTest(); // runs both background jobs

        Assert.areEqual(2, fake.calls, 'one Google call per job');
        Assert.areEqual(2, [SELECT COUNT() FROM Notification_Log__c WHERE Notification_Key__c IN ('TEST-KEY-A', 'TEST-KEY-B') AND Status__c = 'Sent']);
    }

    @IsTest
    static void creatingAReturnSendsOneNotification() {
        FakeGoogle fake = new FakeGoogle();
        Test.setMock(HttpCalloutMock.class, fake);
        Order o = TestDataFactory.makeOrder('T-7001', 'Delivered', Date.today().addDays(-3),
            new List<Decimal>{ 80 }, 'Standard');

        Test.startTest();
        CreateReturnRequest.Request q = new CreateReturnRequest.Request();
        q.orderReference = 'T-7001';
        q.reason = 'Defective';
        q.customerConfirmed = true;
        CreateReturnRequest.Result r = CreateReturnRequest.createOne(q);
        Test.stopTest(); // runs the background notification job

        Assert.isTrue(r.success, r.message);
        Assert.areEqual(1, [SELECT COUNT() FROM Notification_Log__c WHERE Notification_Key__c LIKE 'RETURN-%-REQUESTED'],
            'one return notification expected');
        Assert.areEqual(1, fake.calls);
    }

    @IsTest
    static void escalatingACaseSendsOneNotification() {
        FakeGoogle fake = new FakeGoogle();
        Test.setMock(HttpCalloutMock.class, fake);
        TestDataFactory.makeOrder('T-7002', 'Delayed', null, new List<Decimal>{ 80 }, 'Standard');

        Test.startTest();
        EscalateSupportCase.Request q = new EscalateSupportCase.Request();
        q.orderReference = 'T-7002';
        q.escalationReason = 'Overdue';
        EscalateSupportCase.Result r = EscalateSupportCase.escalateOne(q);
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        Assert.areEqual(1, [SELECT COUNT() FROM Notification_Log__c WHERE Notification_Key__c LIKE 'CASE-%-ESCALATED']);
        Assert.areEqual(1, fake.calls);
    }
}