trigger CaseEscalationTrigger on Case (after insert) {
    Set<Id> ids = new Set<Id>();
    for (Case c : Trigger.new) {
        if (c.Order__c != null) {
            ids.add(c.Id);
        }
    }
    if (!ids.isEmpty()) {
        NotificationQueueable.notifyCasesEscalated(ids);
    }
}