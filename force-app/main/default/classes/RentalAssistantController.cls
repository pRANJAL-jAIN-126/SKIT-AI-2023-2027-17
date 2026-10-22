/**
 * Fallback chat shell (TDD 8.6) used when Agentforce cannot be enabled. The LLM (Prompt Builder template
 * Rental_Assistant_Intent) only classifies the message into structured JSON; every action is executed by the
 * same Apex as the Agentforce actions (AgentSearchVehicles, AgentCreateBooking, ...), so only the chat shell
 * differs. The customer identity is always the logged-in portal user.
 */
public with sharing class RentalAssistantController {
    public static final String TEMPLATE = 'Rental_Assistant_Intent';
    private static final Pattern ID_IN_TEXT = Pattern.compile('id: ([a-zA-Z0-9]{15,18})');

    /** Pluggable intent source (test seam; default = Prompt Builder). */
    public interface IntentProvider {
        String classify(String message, String historyJson);
    }

    @TestVisible
    private static IntentProvider providerOverride;

    public class Link {
        @AuraEnabled public String label;
        @AuraEnabled public String url;
        public Link(String label, String url) {
            this.label = label;
            this.url = url;
        }
    }

    public class ChatResponse {
        @AuraEnabled public String reply;
        @AuraEnabled public String intent;
        @AuraEnabled public List<RentalDtos.VehicleDTO> vehicles = new List<RentalDtos.VehicleDTO>();
        @AuraEnabled public RentalDtos.BookingDTO booking;
        @AuraEnabled public List<Link> links = new List<Link>();
    }

    @AuraEnabled
    public static ChatResponse chat(String message, String historyJson) {
        try {
            if (String.isBlank(message)) {
                throw new BookingException('Please type a message.');
            }
            Map<String, Object> intent = parseIntent(provider().classify(message.left(2000), (historyJson ?? '[]').right(20000)));
            return handle(intent, historyJson);
        } catch (Exception e) {
            throw RentalErrors.toAura(e);
        }
    }

    @TestVisible
    private static ChatResponse handle(Map<String, Object> j, String historyJson) {
        ChatResponse res = new ChatResponse();
        res.intent = str(j, 'intent') ?? 'unknown';
        String llmReply = str(j, 'reply');
        switch on res.intent {
            when 'search' {
                return search(j, res, llmReply);
            }
            when 'book' {
                return book(j, res, historyJson);
            }
            when 'get_booking' {
                requireLogin();
                AgentGetBooking.Res r = AgentGetBooking.lookup(null, str(j, 'bookingNumber'));
                res.reply = str(j, 'bookingNumber') == null ? 'Which booking number (for example BK-1042)?' : r.message;
            }
            when 'cancel' {
                requireLogin();
                if (str(j, 'bookingNumber') == null) {
                    res.reply = 'Which booking would you like to cancel (for example BK-1042)?';
                } else {
                    AgentCancelBooking.Res r = AgentCancelBooking.cancel(null, str(j, 'bookingNumber'), j.get('confirmed') == true);
                    res.reply = r.cancelled ? r.message : r.message.replace('Ask the customer to confirm explicitly before cancelling.', 'Do you want me to cancel it? Please reply yes to confirm.');
                }
            }
            when 'payment_link' {
                requireLogin();
                AgentGetPaymentLink.Res r = AgentGetPaymentLink.link(null, str(j, 'bookingNumber'));
                res.reply = r.message;
                if (r.url != null) {
                    res.links.add(new Link('Open link', r.url));
                }
            }
            when 'escalate' {
                res.reply = 'I am sorry about that. Please contact our team at ' + RentalConfig.get().Support_Email__c +
                    ' and a staff member will help you.';
            }
            when 'policy', 'smalltalk' {
                res.reply = llmReply ?? 'How can I help you with your rental?';
            }
            when else {
                res.reply = 'I can help you find a car, hold a booking, check or cancel a booking. What would you like to do?';
            }
        }
        return res;
    }

    private static ChatResponse search(Map<String, Object> j, ChatResponse res, String llmReply) {
        Datetime pickup = dt(j, 'pickup'), ret = dt(j, 'return');
        String city = str(j, 'city');
        List<String> missing = new List<String>();
        if (pickup == null) {
            missing.add('pickup date and time');
        }
        if (ret == null) {
            missing.add('return date and time');
        }
        if (city == null) {
            missing.add('city');
        }
        if (!missing.isEmpty()) {
            res.reply = 'Sure. Could you tell me the ' + String.join(missing, ', ') + '?';
            return res;
        }
        AgentSearchVehicles.Req r = new AgentSearchVehicles.Req();
        r.pickupDateTime = pickup;
        r.returnDateTime = ret;
        r.city = city;
        r.category = str(j, 'category');
        r.transmission = str(j, 'transmission');
        r.fuelType = str(j, 'fuelType');
        r.minSeats = j.get('minSeats') == null ? null : Integer.valueOf(String.valueOf(j.get('minSeats')));
        r.maxDailyRate = j.get('maxDailyRate') == null ? null : Decimal.valueOf(String.valueOf(j.get('maxDailyRate')));
        AgentSearchVehicles.Res found = AgentSearchVehicles.search(r);
        res.reply = found.summary + (found.vehicleIds.isEmpty() ? '' : '\nWhich one would you like?');
        if (!found.vehicleIds.isEmpty()) {
            VehicleSearchService.SearchRequest sr = new VehicleSearchService.SearchRequest();
            sr.startDt = pickup;
            sr.endDt = ret;
            sr.city = city;
            Set<String> ids = new Set<String>(found.vehicleIds);
            for (RentalDtos.VehicleDTO v : VehicleSearchService.searchWithQuotes(sr)) {
                if (ids.contains(v.id) && res.vehicles.size() < 3) {
                    res.vehicles.add(v);
                }
            }
        }
        return res;
    }

    private static ChatResponse book(Map<String, Object> j, ChatResponse res, String historyJson) {
        requireLogin();
        Datetime pickup = dt(j, 'pickup'), ret = dt(j, 'return');
        Id vehicleId = resolveVehicle(str(j, 'vehicleRef'), historyJson);
        if (vehicleId == null || pickup == null || ret == null) {
            res.reply = 'Which car and which dates would you like to book? Search first and pick one of the results.';
            return res;
        }
        if (j.get('confirmed') != true) {
            List<Vehicle__c> v = [SELECT Make__c, Model__c, Daily_Rate__c, Security_Deposit__c FROM Vehicle__c WHERE Id = :vehicleId WITH USER_MODE LIMIT 1];
            if (v.isEmpty()) {
                res.reply = 'That vehicle is not available. Please search again.';
                return res;
            }
            PricingService.Quote q = PricingService.calculate(v[0], pickup, ret);
            res.reply = 'To confirm: ' + v[0].Make__c + ' ' + v[0].Model__c + ', ' + AgentSupport.range(pickup, ret) + ', total ' +
                AgentSupport.inr(q.total) + ' incl. GST plus refundable deposit ' + AgentSupport.inr(q.deposit) +
                '. Shall I hold it for you? (yes / no)';
            return res;
        }
        AgentCreateBooking.Req r = new AgentCreateBooking.Req();
        r.vehicleId = vehicleId;
        r.pickupDateTime = pickup;
        r.returnDateTime = ret;
        r.sessionId = 'fallback-chat';
        AgentCreateBooking.Res created = AgentCreateBooking.create(r);
        res.reply = created.message;
        if (created.success) {
            if (created.kycStatus != 'Verified') {
                res.links.add(new Link('Verify licence', created.verifyUrl));
            }
            res.links.add(new Link('Pay now', created.paymentUrl));
        }
        return res;
    }

    /** vehicleRef may be a vehicle Id or 1-3 = position in the last suggestion list found in the history. */
    @TestVisible
    private static Id resolveVehicle(String ref, String historyJson) {
        Id direct = CustomerContext.toId(ref);
        if (direct != null && direct.getSobjectType() == Vehicle__c.SObjectType) {
            return direct;
        }
        if (ref == null || !ref.trim().isNumeric() || String.isBlank(historyJson)) {
            return null;
        }
        Integer index = Integer.valueOf(ref.trim());
        List<Object> history;
        try {
            history = (List<Object>) JSON.deserializeUntyped(historyJson);
        } catch (Exception e) {
            return null;
        }
        for (Integer i = history.size() - 1; i >= 0; i--) {
            Map<String, Object> turn = (Map<String, Object>) history[i];
            String text = String.valueOf(turn.get('text'));
            if (turn.get('role') != 'user' && text != null && text.contains('id: ')) {
                Matcher m = ID_IN_TEXT.matcher(text);
                Integer n = 0;
                while (m.find()) {
                    n++;
                    if (n == index) {
                        return CustomerContext.toId(m.group(1));
                    }
                }
                return null;
            }
        }
        return null;
    }

    private static void requireLogin() {
        CustomerContext.requireCustomer();
    }

    @TestVisible
    private static Map<String, Object> parseIntent(String raw) {
        String body = raw == null ? '' : raw.trim();
        Integer start = body.indexOf('{'), finish = body.lastIndexOf('}');
        if (start < 0 || finish <= start) {
            return new Map<String, Object>{ 'intent' => 'unknown' };
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(body.substring(start, finish + 1));
        } catch (Exception e) {
            return new Map<String, Object>{ 'intent' => 'unknown' };
        }
    }

    private static String str(Map<String, Object> j, String key) {
        Object v = j.get(key);
        return v == null || String.isBlank(String.valueOf(v)) || String.valueOf(v) == 'null' ? null : String.valueOf(v).trim();
    }

    private static Datetime dt(Map<String, Object> j, String key) {
        String v = str(j, key);
        if (v == null) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + v + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    private static IntentProvider provider() {
        return providerOverride ?? new PromptTemplateIntentProvider();
    }

    /** Prompt Builder implementation – requires Einstein generative AI. */
    public class PromptTemplateIntentProvider implements IntentProvider {
        public String classify(String message, String historyJson) {
            ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.isPreview = false;
            input.inputParams = new Map<String, ConnectApi.WrappedValue>{
                'Input:UserMessage' => wrap(message),
                'Input:ConversationHistory' => wrap(historyJson),
                'Input:CurrentDateTime' => wrap(System.now().format('yyyy-MM-dd\'T\'HH:mm:ssXXX', AgentSupport.TIME_ZONE))
            };
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation out = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(TEMPLATE, input);
            if (out == null || out.generations == null || out.generations.isEmpty()) {
                throw new BookingException('The assistant is unavailable right now. Please use the search page.');
            }
            return out.generations[0].text;
        }

        private ConnectApi.WrappedValue wrap(String value) {
            ConnectApi.WrappedValue w = new ConnectApi.WrappedValue();
            w.value = value;
            return w;
        }
    }
}