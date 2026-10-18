/**
 * Resolves the customer (Contact) for the current request. The Contact Id is always taken from the
 * authenticated session, never from browser input or LLM-generated text (TDD 8.1, 8.4, 11.2).
 */
public with sharing class CustomerContext {
    /** Test hook: simulates a logged-in Experience Cloud customer. */
    @TestVisible
    private static Id testContactId;
    /** Test hook: simulates the guest user. */
    @TestVisible
    private static Boolean testIsGuest;

    public static Boolean isGuest() {
        return testIsGuest != null ? testIsGuest : UserInfo.getUserType() == 'Guest';
    }

    /** Contact of the running user (portal customers), or null for internal users and guests. */
    public static Id runningUserContactId() {
        if (testContactId != null) {
            return testContactId;
        }
        if (isGuest()) {
            return null;
        }
        List<User> users = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        return users.isEmpty() ? null : users[0].ContactId;
    }

    /** Portal entry points: the caller must be a logged-in customer. */
    public static Id requireCustomer() {
        if (isGuest()) {
            throw new BookingException('Please log in to continue.');
        }
        Id contactId = runningUserContactId();
        if (contactId == null) {
            throw new BookingException('A customer account is required for this action.');
        }
        return contactId;
    }

    /**
     * Agent entry points (no session). Strips unresolved merge field literals before validating.
     */
    public static Id resolveForAgent(String suppliedContactId) {
        return resolveForAgent(suppliedContactId, null);
    }

    /**
     * Agent entry points. Resolution order:
     * 1. Running user ContactId (works when agent runs as the authenticated Experience Cloud user).
     * 2. Supplied contact ID (from agent session context binding).
     * 3. MessagingSession lookup via sessionId (Experience Cloud Agentforce channel fallback).
     * Unresolved merge field literals like {!$User.ContactId} are stripped before validation.
     */
    public static Id resolveForAgent(String suppliedContactId, String sessionId) {
        // Strip unresolved merge field literals that Agent Builder passes through un-substituted
        String cleaned = suppliedContactId;
        if (!String.isBlank(cleaned) && cleaned.trim().startsWith('{!')) {
            cleaned = null;
        }

        Id own = runningUserContactId();
        Id supplied = toId(cleaned);

        if (own != null) {
            if (supplied != null && supplied != own) {
                throw new BookingException('You can only access your own bookings.');
            }
            return own;
        }

        if (supplied != null && supplied.getSobjectType() == Contact.SObjectType) {
            if ([SELECT COUNT() FROM Contact WHERE Id = :supplied WITH SYSTEM_MODE] > 0) {
                return supplied;
            }
        }

        // Last resort: resolve from the Agentforce messaging session
        Id fromSession = contactFromSession(sessionId);
        if (fromSession != null) {
            return fromSession;
        }

        throw new BookingException('I could not identify your customer account. Please log in to the portal and try again.');
    }

    /**
     * Looks up the Contact from a MessagingSession ID (Experience Cloud Agentforce channel).
     * Uses dynamic SOQL so it degrades gracefully if MessagingSession is unavailable.
     */
    private static Id contactFromSession(String sessionId) {
        if (String.isBlank(sessionId)) {
            return null;
        }
        try {
            Id sid = Id.valueOf(sessionId.trim());
            List<SObject> rows = Database.query(
                'SELECT MessagingEndUser.ContactId FROM MessagingSession WHERE Id = :sid WITH SYSTEM_MODE LIMIT 1'
            );
            if (!rows.isEmpty()) {
                SObject eu = rows[0].getSObject('MessagingEndUser');
                if (eu != null) {
                    return (Id) eu.get('ContactId');
                }
            }
        } catch (Exception e) {
            // MessagingSession unavailable or sessionId is not a MessagingSession — expected in some channel types
        }
        return null;
    }

    public static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception e) {
            return null;
        }
    }
}
