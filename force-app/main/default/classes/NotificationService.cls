public with sharing class NotificationService {

    private static final Integer TIMEOUT_MS = 10000;
    private static final String API_NAME = 'Notification (Google Apps Script)';
    private static final String UNAVAILABLE_MSG = 'The notification service is temporarily unavailable. The notification was not sent.';

    public class Outcome {
        public String status;
        public String message;
    }

    public static Outcome send(String notificationKey, String event, String recipient, String subject, String body) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        List<Notification_Log__c> notifs = new List<Notification_Log__c>();
        Outcome o = attempt(notificationKey, event, recipient, subject, body, logs, notifs);
        if (!logs.isEmpty()) {
            insert logs;
        }
        if (!notifs.isEmpty()) {
            List<Database.SaveResult> results = Database.insert(notifs, false);
            if (!results[0].isSuccess()) {
                o.status = 'Duplicate';
                o.message = 'Notification ' + notificationKey + ' was already recorded. Nothing was sent again.';
            }
        }
        return o;
    }

    private static Outcome attempt(String k, String ev, String to, String subj, String body,
                                   List<Integration_Log__c> logs, List<Notification_Log__c> notifs) {
        Outcome o = new Outcome();

        if (String.isBlank(k) || String.isBlank(to) || String.isBlank(subj)) {
            o.status = 'Failed';
            o.message = 'A notification key, recipient, and subject are required.';
            return o;
        }

        Integer already = [SELECT COUNT() FROM Notification_Log__c WHERE Notification_Key__c = :k];
        if (already > 0) {
            o.status = 'Duplicate';
            o.message = 'Notification ' + k + ' was already sent. Nothing was sent again.';
            return o;
        }

        Inventory_Config__c cfg = Inventory_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Web_App_URL__c) || String.isBlank(cfg.API_Key__c)) {
            logs.add(buildLog(0, 'Notification settings are missing.'));
            o.status = 'Failed';
            o.message = UNAVAILABLE_MSG;
            return o;
        }
        String key = cfg.API_Key__c.trim();

        try {
            Map<String, Object> payload = new Map<String, Object>{
                'key' => key,
                'notificationId' => k,
                'event' => ev,
                'to' => to,
                'subject' => subj,
                'body' => body
            };
            HttpRequest req = new HttpRequest();
            req.setEndpoint(cfg.Web_App_URL__c.trim());
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(TIMEOUT_MS);
            HttpResponse res = new Http().send(req);

            Integer hops = 0;
            while (isRedirect(res.getStatusCode()) && hops < 3 && !String.isBlank(res.getHeader('Location'))) {
                HttpRequest follow = new HttpRequest();
                follow.setEndpoint(res.getHeader('Location'));
                follow.setMethod('GET');
                follow.setTimeout(TIMEOUT_MS);
                res = new Http().send(follow);
                hops++;
            }

            Integer code = res.getStatusCode();
            if (code != 200) {
                logs.add(buildLog(code, 'Unexpected HTTP status ' + code + ' from the notification service.'));
                o.status = 'Failed';
                o.message = UNAVAILABLE_MSG;
                return o;
            }

            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (parsed.containsKey('error')) {
                logs.add(buildLog(code, 'The notification service returned an error: ' + String.valueOf(parsed.get('error'))));
                o.status = 'Failed';
                o.message = UNAVAILABLE_MSG;
                return o;
            }

            String st = String.valueOf(parsed.get('status'));
            if (st != 'sent' && st != 'duplicate') {
                logs.add(buildLog(code, 'Unexpected answer from the notification service.'));
                o.status = 'Failed';
                o.message = UNAVAILABLE_MSG;
                return o;
            }

            logs.add(buildLog(code, null));
            notifs.add(new Notification_Log__c(
                Notification_Key__c = k,
                Event__c = (ev == null) ? null : ev.abbreviate(40),
                Recipient__c = to,
                Subject__c = subj.abbreviate(255),
                Status__c = (st == 'sent') ? 'Sent' : 'Duplicate'
            ));
            o.status = (st == 'sent') ? 'Sent' : 'Duplicate';
            o.message = (st == 'sent') ? 'Notification ' + k + ' sent.' : 'Notification ' + k + ' had already been sent. Nothing was sent again.';
            return o;
        } catch (Exception e) {
            String msg = e.getMessage() == null ? 'Unknown error' : e.getMessage().replace(key, '***');
            logs.add(buildLog(0, e.getTypeName() + ': ' + msg));
            o.status = 'Failed';
            o.message = UNAVAILABLE_MSG;
            return o;
        }
    }

    private static Boolean isRedirect(Integer code) {
        return code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
    }

    private static Integration_Log__c buildLog(Integer code, String err) {
        return new Integration_Log__c(
            API__c = API_NAME,
            Response_Code__c = code,
            Error__c = err,
            Failed__c = (err != null),
            Timestamp__c = System.now()
        );
    }
}