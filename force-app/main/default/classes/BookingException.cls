/**
 * Business exception raised by the rental service layer. Its message is always safe to show to a
 * customer; controllers translate it into an AuraHandledException (TDD 9.2).
 */
public class BookingException extends Exception {
}