@IsTest
public class TestDataFactory {

    public static String code(String orderRef, Integer line) {
        return 'TST-' + orderRef + '-' + line;
    }

    public static Order makeOrder(String ref, String fulfillment, Date delivered, List<Decimal> linePrices, String tier) {
        Account a = new Account(Name = 'Test ' + ref + ' Household', Customer_Tier__c = tier);
        insert a;
        Contact c = new Contact(FirstName = 'Test', LastName = ref, AccountId = a.Id, Email = 'test.' + ref.toLowerCase() + '@example.com');
        insert c;
        Id stdId = Test.getStandardPricebookId();
        Order o = new Order(
            AccountId = a.Id,
            CustomerAuthorizedById = c.Id,
            Pricebook2Id = stdId,
            EffectiveDate = Date.today().addDays(-10),
            Status = 'Draft',
            Order_Reference__c = ref,
            Fulfillment_Status__c = fulfillment,
            Delivered_Date__c = delivered
        );
        insert o;
        Integer i = 0;
        for (Decimal price : linePrices) {
            i++;
            Product2 p = new Product2(Name = 'Test Product ' + ref + '-' + i, ProductCode = code(ref, i), IsActive = true);
            insert p;
            PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdId, Product2Id = p.Id, UnitPrice = price, IsActive = true);
            insert pbe;
            insert new OrderItem(OrderId = o.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = price);
        }
        return o;
    }
}