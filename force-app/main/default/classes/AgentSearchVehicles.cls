/**
 * Agentforce action "Search Available Vehicles" (TDD 8.3, 9.7). Thin wrapper over VehicleSearchService – the
 * only source of availability for the agent. Returns up to 5 vehicles as plain text built from real records.
 * Agent actions receive one request per conversation turn, so the per-request service call is bounded.
 */
public with sharing class AgentSearchVehicles {
    public static final Integer MAX_SUGGESTIONS = 5;

    public class Req {
        @InvocableVariable(required=true label='Pickup date-time' description='Pickup as ISO 8601 date-time')
        public Datetime pickupDateTime;
        @InvocableVariable(required=true label='Return date-time' description='Return as ISO 8601 date-time')
        public Datetime returnDateTime;
        @InvocableVariable(required=true label='City' description='City of the pickup branch, e.g. Jaipur')
        public String city;
        @InvocableVariable(label='Category' description='Hatchback, Sedan, SUV, MUV, Luxury or Electric')
        public String category;
        @InvocableVariable(label='Minimum seats')
        public Integer minSeats;
        @InvocableVariable(label='Transmission' description='Manual or Automatic')
        public String transmission;
        @InvocableVariable(label='Fuel type' description='Petrol, Diesel, CNG or Electric')
        public String fuelType;
        @InvocableVariable(label='Max daily rate INR')
        public Decimal maxDailyRate;
    }

    public class Res {
        @InvocableVariable(description='Readable list of up to 5 matching vehicles with id, price per day and total')
        public String summary;
        @InvocableVariable(description='Ids of the vehicles listed in the summary, in the same order')
        public List<String> vehicleIds = new List<String>();
    }

    @InvocableMethod(
        label='Search Available Vehicles'
        description='Finds vehicles that are free for the full requested period. Use only this action for availability.'
        category='Smart Car Rental'
    )
    public static List<Res> run(List<Req> reqs) {
        List<Res> out = new List<Res>();
        for (Req r : reqs) {
            out.add(search(r));
        }
        return out;
    }

    public static Res search(Req r) {
        Res res = new Res();
        try {
            VehicleSearchService.SearchRequest sr = new VehicleSearchService.SearchRequest();
            sr.startDt = r.pickupDateTime;
            sr.endDt = r.returnDateTime;
            sr.city = r.city;
            sr.category = r.category;
            sr.minSeats = r.minSeats;
            sr.transmission = r.transmission;
            sr.fuelType = r.fuelType;
            sr.maxDailyRate = r.maxDailyRate;
            List<RentalDtos.VehicleDTO> vehicles = VehicleSearchService.searchWithQuotes(sr);
            if (vehicles.isEmpty()) {
                res.summary = 'No vehicles are free from ' + AgentSupport.range(r.pickupDateTime, r.returnDateTime) +
                    (String.isBlank(r.city) ? '' : ' in ' + r.city) + ' with these filters. Suggest different dates or fewer filters.';
                return res;
            }
            List<String> lines = new List<String>{
                'Vehicles free from ' + AgentSupport.range(r.pickupDateTime, r.returnDateTime) + ':'
            };
            Integer n = 0;
            for (RentalDtos.VehicleDTO v : vehicles) {
                if (n == MAX_SUGGESTIONS) {
                    break;
                }
                n++;
                res.vehicleIds.add(v.id);
                lines.add(
                    n + ') ' + v.make + ' ' + v.model + ' (' + v.category + ', ' + v.transmission + ', ' + v.fuelType + ', ' +
                    v.seats + ' seats, ' + v.branchName + ') - id: ' + v.id + ' - ' + AgentSupport.inr(v.dailyRate) + '/day -> ' +
                    AgentSupport.inr(v.subtotal) + ' for ' + v.days + (v.days == 1 ? ' day' : ' days') + ' (' +
                    AgentSupport.inr(v.total) + ' incl. GST, plus refundable deposit ' + AgentSupport.inr(v.deposit) + ')'
                );
            }
            res.summary = String.join(lines, '\n');
        } catch (Exception e) {
            res.summary = 'Search not possible: ' + RentalErrors.friendlyMessage(e);
        }
        return res;
    }
}