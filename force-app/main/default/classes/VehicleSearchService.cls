/**
 * Live availability search (TDD 9.3, D1). Availability is derived from Booking__c date overlap, not from
 * Vehicle__c.Status__c, which only reflects the car's physical state.
 */
public with sharing class VehicleSearchService {
    public static final Integer MAX_RESULTS = 50;

    public class SearchRequest {
        @AuraEnabled public Datetime startDt { get; set; }
        @AuraEnabled public Datetime endDt { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String transmission { get; set; }
        @AuraEnabled public String fuelType { get; set; }
        @AuraEnabled public Integer minSeats { get; set; }
        @AuraEnabled public Decimal maxDailyRate { get; set; }
    }

    /** Vehicles that are NOT free for the whole [startDt, endDt) range. Overlap is strict (back-to-back is allowed). */
    public static Set<Id> busyVehicleIds(Datetime startDt, Datetime endDt) {
        return new Availability().busy(startDt, endDt, null);
    }

    public static Set<Id> busyVehicleIds(Datetime startDt, Datetime endDt, Set<Id> vehicleIds) {
        return new Availability().busy(startDt, endDt, vehicleIds);
    }

    public static List<Vehicle__c> searchAvailable(SearchRequest r) {
        if (r == null) {
            throw new BookingException('Please choose a valid pickup and return time.');
        }
        BookingService.validateDates(r.startDt, r.endDt);
        Set<Id> busy = busyVehicleIds(r.startDt, r.endDt);

        Map<String, Object> binds = new Map<String, Object>{ 'busy' => busy };
        String q =
            'SELECT Id, Name, Registration_Number__c, Make__c, Model__c, Year__c, Category__c, Seats__c, ' +
            'Transmission__c, Fuel_Type__c, Daily_Rate__c, Security_Deposit__c, Image_URL__c, Status__c, ' +
            'Branch__c, Branch__r.Name, Branch__r.City__c FROM Vehicle__c ' +
            'WHERE Status__c NOT IN (\'Maintenance\', \'Retired\') AND Id NOT IN :busy';
        if (String.isNotBlank(r.city)) {
            q += ' AND Branch__r.City__c = :city';
            binds.put('city', r.city.trim());
        }
        if (String.isNotBlank(r.category)) {
            q += ' AND Category__c = :category';
            binds.put('category', r.category);
        }
        if (r.minSeats != null && r.minSeats > 0) {
            q += ' AND Seats__c >= :minSeats';
            binds.put('minSeats', r.minSeats);
        }
        if (String.isNotBlank(r.transmission)) {
            q += ' AND Transmission__c = :transmission';
            binds.put('transmission', r.transmission);
        }
        if (String.isNotBlank(r.fuelType)) {
            q += ' AND Fuel_Type__c = :fuelType';
            binds.put('fuelType', r.fuelType);
        }
        if (r.maxDailyRate != null && r.maxDailyRate > 0) {
            q += ' AND Daily_Rate__c <= :maxDailyRate';
            binds.put('maxDailyRate', r.maxDailyRate);
        }
        q += ' ORDER BY Daily_Rate__c ASC LIMIT ' + MAX_RESULTS;
        // USER_MODE enforces CRUD/FLS + sharing of the caller (guest / customer / agent user).
        return (List<Vehicle__c>) Database.queryWithBinds(q, binds, AccessLevel.USER_MODE);
    }

    /** Search + quote, the shape both the portal and the agent consume. */
    public static List<RentalDtos.VehicleDTO> searchWithQuotes(SearchRequest r) {
        List<RentalDtos.VehicleDTO> result = new List<RentalDtos.VehicleDTO>();
        for (Vehicle__c v : searchAvailable(r)) {
            result.add(new RentalDtos.VehicleDTO(v, PricingService.calculate(v, r.startDt, r.endDt)));
        }
        return result;
    }

    /**
     * Runs WITHOUT sharing on purpose (documented exception, plan D-02): the overlap check must see every
     * customer's bookings, while customers and guests can only see their own. It returns vehicle Ids only,
     * so no booking data is exposed.
     */
    private without sharing class Availability {
        Set<Id> busy(Datetime startDt, Datetime endDt, Set<Id> scope) {
            Datetime nowDt = System.now();
            Set<Id> ids = new Set<Id>();
            Boolean scoped = scope != null;
            // 1) any blocking booking whose time range overlaps the requested range
            List<AggregateResult> overlaps = scoped
                ? [
                      SELECT Vehicle__c v
                      FROM Booking__c
                      WHERE
                          Vehicle__c IN :scope
                          AND Start_DateTime__c < :endDt
                          AND End_DateTime__c > :startDt
                          AND (Status__c IN ('Confirmed', 'Active')
                          OR (Status__c = 'Pending Payment'
                          AND Hold_Expires_At__c > :nowDt))
                      WITH SYSTEM_MODE
                      GROUP BY Vehicle__c
                  ]
                : [
                      SELECT Vehicle__c v
                      FROM Booking__c
                      WHERE
                          Start_DateTime__c < :endDt
                          AND End_DateTime__c > :startDt
                          AND (Status__c IN ('Confirmed', 'Active')
                          OR (Status__c = 'Pending Payment'
                          AND Hold_Expires_At__c > :nowDt))
                      WITH SYSTEM_MODE
                      GROUP BY Vehicle__c
                  ];
            for (AggregateResult ar : overlaps) {
                ids.add((Id) ar.get('v'));
            }
            // 2) cars still out past their planned return are unavailable
            for (Booking__c b : [
                SELECT Vehicle__c
                FROM Booking__c
                WHERE Status__c = 'Active' AND Is_Overdue__c = TRUE
                WITH SYSTEM_MODE
            ]) {
                ids.add(b.Vehicle__c);
            }
            if (scoped) {
                ids.retainAll(scope);
            }
            return ids;
        }
    }
}