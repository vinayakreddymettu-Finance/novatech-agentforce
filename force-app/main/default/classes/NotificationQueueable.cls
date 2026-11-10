public with sharing class NotificationQueueable implements Queueable, Database.AllowsCallouts {

    public class Payload {
        public String key;
        public String event;
        public String recipient;
        public String subject;
        public String body;
        public Payload(String key, String event, String recipient, String subject, String body) {
            this.key = key;
            this.event = event;
            this.recipient = recipient;
            this.subject = subject;
            this.body = body;
        }
    }

    private Payload payload;

    public NotificationQueueable(Payload payload) {
        this.payload = payload;
    }

    public void execute(QueueableContext context) {
        NotificationService.send(payload.key, payload.event, payload.recipient, payload.subject, payload.body);
    }

    private static void enqueueAll(List<Payload> payloads) {
        for (Payload p : payloads) {
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new NotificationQueueable(p));
            }
        }
    }

    private static String money(Decimal d) {
        return d == null ? '0.00' : String.valueOf(d.setScale(2));
    }

    public static void notifyReturnsCreated(Set<Id> returnIds) {
        List<Payload> out = new List<Payload>();
        for (Return_Request__c r : [
            SELECT Id, Name, Refund_Amount__c, Order__r.Order_Reference__c, Order__r.CustomerAuthorizedBy.Email
            FROM Return_Request__c WHERE Id IN :returnIds
        ]) {
            String to = (r.Order__r != null && r.Order__r.CustomerAuthorizedBy != null) ? r.Order__r.CustomerAuthorizedBy.Email : null;
            if (String.isBlank(to)) { continue; }
            String ref = r.Order__r.Order_Reference__c;
            out.add(new Payload(
                'RETURN-' + r.Id + '-REQUESTED',
                'Return Requested',
                to,
                'Return request ' + r.Name + ' received for order ' + ref,
                'We have received your return request ' + r.Name + ' for order ' + ref
                    + ' (refund amount $' + money(r.Refund_Amount__c) + '). We will let you know the outcome.'
            ));
        }
        enqueueAll(out);
    }

    public static void notifyApprovalDecisions(Set<Id> approvalIds) {
        List<Payload> out = new List<Payload>();
        for (Refund_Approval__c a : [
            SELECT Id, Name, Decision__c, Amount__c, Return_Request__r.Name,
                   Return_Request__r.Order__r.Order_Reference__c,
                   Return_Request__r.Order__r.CustomerAuthorizedBy.Email
            FROM Refund_Approval__c WHERE Id IN :approvalIds
        ]) {
            if (a.Decision__c != 'Approved' && a.Decision__c != 'Rejected') { continue; }
            Order o = (a.Return_Request__r == null) ? null : a.Return_Request__r.Order__r;
            String to = (o != null && o.CustomerAuthorizedBy != null) ? o.CustomerAuthorizedBy.Email : null;
            if (String.isBlank(to)) { continue; }
            String ref = o.Order_Reference__c;
            String verdict = (a.Decision__c == 'Approved') ? 'approved' : 'not approved';
            out.add(new Payload(
                'APPROVAL-' + a.Id + '-' + a.Decision__c.toUpperCase(),
                'Refund ' + a.Decision__c,
                to,
                'Your refund for order ' + ref + ' was ' + verdict,
                'Your refund of $' + money(a.Amount__c) + ' for order ' + ref + ' (' + a.Return_Request__r.Name + ') was ' + verdict + '.'
            ));
        }
        enqueueAll(out);
    }

    public static void notifyCasesEscalated(Set<Id> caseIds) {
        List<Payload> out = new List<Payload>();
        for (Case c : [
            SELECT Id, CaseNumber, Priority, Contact.Email, Order__r.Order_Reference__c
            FROM Case WHERE Id IN :caseIds AND Order__c != null
        ]) {
            String to = (c.Contact != null) ? c.Contact.Email : null;
            if (String.isBlank(to)) { continue; }
            String ref = c.Order__r.Order_Reference__c;
            out.add(new Payload(
                'CASE-' + c.Id + '-ESCALATED',
                'Case Escalated',
                to,
                'Support case ' + c.CaseNumber + ' opened for order ' + ref,
                'We have opened support case ' + c.CaseNumber + ' (priority ' + c.Priority + ') for order ' + ref
                    + '. A member of our team will follow up with you.'
            ));
        }
        enqueueAll(out);
    }
}