@IsTest
private class CustomerPermissionAssignerTest {
    /** Portal users need an account owned by a user with a role. */
    private static User ownerWithRole() {
        UserRole role = new UserRole(Name = 'Rental Test Owner Role');
        insert role;
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User owner = new User(
            Alias = 'rowner',
            Email = 'rental.owner@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Owner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_IN',
            TimeZoneSidKey = 'Asia/Kolkata',
            ProfileId = admin.Id,
            UserRoleId = role.Id,
            Username = 'rental.owner.' + System.currentTimeMillis() + '@example.test'
        );
        insert owner;
        return owner;
    }

    private static User portalUser(String profileName, Id contactId, String suffix) {
        return new User(
            Alias = 'cust' + suffix,
            Email = 'customer' + suffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Customer' + suffix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_IN',
            TimeZoneSidKey = 'Asia/Kolkata',
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1].Id,
            ContactId = contactId,
            Username = 'customer' + suffix + '.' + System.currentTimeMillis() + '@example.test'
        );
    }

    private static Set<String> permSetNames(Id userId) {
        Set<String> names = new Set<String>();
        for (PermissionSetAssignment a : [
            SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSet.IsOwnedByProfile = FALSE
        ]) {
            names.add(a.PermissionSet.Name);
        }
        return names;
    }

    @IsTest
    static void newSelfRegisteredCustomerGetsPortalPermissionSets() {
        User owner = ownerWithRole();
        User customer;
        System.runAs(owner) {
            Account acc = new Account(Name = 'Smart Car Rental Customers (test)', OwnerId = owner.Id);
            insert acc;
            Contact c = new Contact(FirstName = 'New', LastName = 'Signup', AccountId = acc.Id);
            insert c;
            customer = portalUser('Customer Community Login User', c.Id, '1');
            Test.startTest();
            insert customer; // UserTrigger -> @future assignment
            Test.stopTest();
        }
        Set<String> names = permSetNames(customer.Id);
        Assert.isTrue(names.contains('Rental_Customer'), 'customer can use the portal: ' + names);
        Assert.isTrue(names.contains('Rental_Integration'), 'customer can verify KYC / pay: ' + names);
        Assert.areEqual(0, CustomerPermissionAssigner.assign(new Set<Id>{ customer.Id }), 'idempotent: nothing to add twice');
    }

    @IsTest
    static void internalUsersAreIgnored() {
        User owner = ownerWithRole();
        Assert.areEqual(0, CustomerPermissionAssigner.assign(new Set<Id>{ owner.Id }), 'not a portal customer');
        Assert.isFalse(permSetNames(owner.Id).contains('Rental_Customer'));
    }
}
