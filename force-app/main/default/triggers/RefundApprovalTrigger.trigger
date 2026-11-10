trigger RefundApprovalTrigger on Refund_Approval__c (before insert, before update, after insert, after update) {

    Decimal threshold = SubmitRefundApproval.APPROVAL_THRESHOLD;

    if (Trigger.isBefore && Trigger.isInsert) {
        for (Refund_Approval__c ap : Trigger.new) {
            if (ap.Amount__c != null && ap.Amount__c >= threshold && ap.Decision__c != 'Pending') {
                ap.addError('Refunds of $' + threshold + ' or more must start as Pending and be decided by a manager.');
            }
        }
    }

    if (Trigger.isBefore && Trigger.isUpdate) {
        for (Refund_Approval__c ap : Trigger.new) {
            Refund_Approval__c oldAp = Trigger.oldMap.get(ap.Id);
            Boolean decisionChanged = oldAp.Decision__c != ap.Decision__c;

            if (oldAp.Amount__c != ap.Amount__c) {
                ap.addError('The approval amount cannot be changed after the approval is created.');
            } else if (decisionChanged && oldAp.Decision__c != 'Pending') {
                ap.addError('This approval has already been decided and cannot be changed.');
            } else if (decisionChanged && oldAp.Reviewer__c != null && oldAp.Reviewer__c != UserInfo.getUserId()) {
                ap.addError('Only the assigned reviewer can approve or reject this refund.');
            }
        }
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        Set<Id> autoApproved = new Set<Id>();
        for (Refund_Approval__c ap : Trigger.new) {
            if (ap.Decision__c == 'Approved') {
                autoApproved.add(ap.Id);
            }
        }
        if (!autoApproved.isEmpty()) {
            NotificationQueueable.notifyApprovalDecisions(autoApproved);
        }
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        Map<Id, String> newStatusByReturn = new Map<Id, String>();
        Set<Id> decidedIds = new Set<Id>();
        for (Refund_Approval__c ap : Trigger.new) {
            Refund_Approval__c oldAp = Trigger.oldMap.get(ap.Id);
            if (oldAp.Decision__c == 'Pending' && (ap.Decision__c == 'Approved' || ap.Decision__c == 'Rejected')) {
                newStatusByReturn.put(ap.Return_Request__c, ap.Decision__c);
                decidedIds.add(ap.Id);
            }
        }
        if (!newStatusByReturn.isEmpty()) {
            List<Return_Request__c> toUpdate = new List<Return_Request__c>();
            for (Return_Request__c rr : [SELECT Id FROM Return_Request__c WHERE Id IN :newStatusByReturn.keySet()]) {
                rr.Status__c = newStatusByReturn.get(rr.Id);
                toUpdate.add(rr);
            }
            update toUpdate;
        }
        if (!decidedIds.isEmpty()) {
            NotificationQueueable.notifyApprovalDecisions(decidedIds);
        }
    }
}