function doGet(e) {
  var params = (e && e.parameter) ? e.parameter : {};
  var expected = PropertiesService.getScriptProperties().getProperty('API_KEY');
  if (!expected || params.key !== expected) {
    return respond_({ error: 'Unauthorized' });
  }
  var sku = (params.sku || '').trim().toUpperCase();
  if (!sku) {
    return respond_({ error: 'Missing sku parameter' });
  }
  var sheet = SpreadsheetApp.getActive().getSheetByName('Inventory');
  if (!sheet) {
    return respond_({ error: 'Inventory tab not found' });
  }
  var values = sheet.getDataRange().getValues();
  var col = {};
  for (var c = 0; c < values[0].length; c++) {
    col[String(values[0][c]).trim()] = c;
  }
  for (var r = 1; r < values.length; r++) {
    if (String(values[r][col.sku]).trim().toUpperCase() === sku) {
      var updated = values[r][col.lastUpdated];
      if (updated instanceof Date) {
        updated = Utilities.formatDate(updated, 'UTC', "yyyy-MM-dd'T'HH:mm:ss'Z'");
      }
      return respond_({
        sku: String(values[r][col.sku]).trim(),
        productName: values[r][col.productName],
        availableQuantity: Number(values[r][col.availableQuantity]),
        warehouse: values[r][col.warehouse],
        lastUpdated: String(updated)
      });
    }
  }
  return respond_({ error: 'SKU not found', sku: sku });
}

function doPost(e) {
  var expected = PropertiesService.getScriptProperties().getProperty('API_KEY');
  var data;
  try {
    data = JSON.parse(e.postData.contents);
  } catch (err) {
    return respond_({ error: 'Invalid JSON' });
  }
  if (!expected || data.key !== expected) {
    return respond_({ error: 'Unauthorized' });
  }
  return respond_(sendNotification_(data));
}

function sendNotification_(data) {
  if (!data.notificationId || !data.to || !data.subject) {
    return { error: 'Missing notificationId, to, or subject' };
  }
  var lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    var ss = SpreadsheetApp.getActive();
    var sh = ss.getSheetByName('Notifications');
    if (!sh) {
      sh = ss.insertSheet('Notifications');
      sh.appendRow(['notificationId', 'event', 'to', 'subject', 'sentAt']);
    }
    var ids = sh.getRange(1, 1, sh.getLastRow(), 1).getValues();
    for (var i = 1; i < ids.length; i++) {
      if (String(ids[i][0]) === String(data.notificationId)) {
        return { status: 'duplicate', notificationId: data.notificationId };
      }
    }
    var owner = Session.getEffectiveUser().getEmail();
    var text = String(data.body || '').substring(0, 2000);
    MailApp.sendEmail({
      to: owner,
      subject: '[SIMULATED to ' + data.to + '] ' + data.subject,
      body: 'Simulated notification (demo only, not sent to the customer)\n\n'
        + 'To: ' + data.to + '\n'
        + 'Event: ' + (data.event || '') + '\n'
        + 'Notification id: ' + data.notificationId + '\n\n'
        + text
    });
    sh.appendRow([data.notificationId, data.event || '', data.to, data.subject, new Date()]);
    return { status: 'sent', notificationId: data.notificationId, to: data.to };
  } finally {
    lock.releaseLock();
  }
}

function respond_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function testNotify() {
  var result = sendNotification_({
    notificationId: 'TEST-' + new Date().getTime(),
    event: 'Test',
    to: 'test.customer@example.com',
    subject: 'Test notification',
    body: 'If you can read this, notifications work.'
  });
  Logger.log(JSON.stringify(result));
}