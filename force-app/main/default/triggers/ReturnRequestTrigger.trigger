trigger ReturnRequestTrigger on Return_Request__c (after insert) {
    NotificationQueueable.notifyReturnsCreated(Trigger.newMap.keySet());
}