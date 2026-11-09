/**
 * Deterministic damage report used when the Prompt Builder call is unavailable (plan D-09). It produces the
 * same five sections as Damage_Report_Summary and, like the prompt, only reports damage that is present in the
 * condition fields or the inspector's notes – it never invents damage. The report is clearly labelled.
 */
public with sharing class RuleBasedDamageReportGenerator implements DamageReportGenerator {
    public static final String LABEL = '[Rule-based report - generative AI unavailable]';
    private static final List<String> FUEL = new List<String>{ 'Empty', '1/4', '1/2', '3/4', 'Full' };
    private static final List<String> CONDITION = new List<String>{ 'Excellent', 'Good', 'Minor Damage', 'Major Damage' };

    public String generate(Vehicle__c vehicle, Inspection__c pickup, Inspection__c ret) {
        List<String> damage = new List<String>();
        String severity = 'None';
        severity = compareCondition('Exterior', pickup.Exterior_Condition__c, ret.Exterior_Condition__c, damage, severity);
        severity = compareCondition('Interior', pickup.Interior_Condition__c, ret.Interior_Condition__c, damage, severity);
        String notes = ret.Damage_Notes__c == null ? '' : ret.Damage_Notes__c.trim();
        if (String.isNotBlank(notes) && notes != (pickup.Damage_Notes__c ?? '').trim()) {
            damage.add('Inspector noted: ' + notes.abbreviate(200));
            if (severity == 'None') {
                severity = 'Minor';
            }
        }
        Decimal distance = (ret.Odometer__c ?? 0) - (pickup.Odometer__c ?? 0);
        Integer fuelDiff = FUEL.indexOf(ret.Fuel_Level__c) - FUEL.indexOf(pickup.Fuel_Level__c);
        String fuelText = (pickup.Fuel_Level__c == null || ret.Fuel_Level__c == null)
            ? 'Not recorded'
            : pickup.Fuel_Level__c + ' -> ' + ret.Fuel_Level__c + (fuelDiff < 0 ? ' (refuelling needed)' : fuelDiff == 0 ? ' (unchanged)' : '');
        String action = severity == 'Major'
            ? 'Hold the vehicle for repair assessment and route the charge for branch manager approval.'
            : severity == 'Minor'
                ? 'Photograph and log the damage; apply the estimated charge if the customer agrees.'
                : 'No action needed; vehicle can return to the fleet.';
        if (fuelDiff < 0 && severity == 'None') {
            action = 'Refuel the vehicle; no damage action needed.';
        }
        List<String> lines = new List<String>{
            LABEL,
            '1) Distance driven: ' + distance.setScale(0) + ' km',
            '2) Fuel difference: ' + fuelText,
            '3) New damage found: ' + (damage.isEmpty() ? 'None' : '\n- ' + String.join(damage, '\n- ')),
            '4) Severity: ' + severity,
            '5) Recommended action: ' + action
        };
        return String.join(lines, '\n');
    }

    private static String compareCondition(String area, String before, String after, List<String> damage, String severity) {
        Integer b = CONDITION.indexOf(before), a = CONDITION.indexOf(after);
        if (a < 2 || a <= b) {
            return severity; // no new damage recorded in this field
        }
        damage.add(area + ' condition changed from ' + (before ?? 'not recorded') + ' to ' + after);
        return after == 'Major Damage' ? 'Major' : (severity == 'Major' ? 'Major' : 'Minor');
    }
}