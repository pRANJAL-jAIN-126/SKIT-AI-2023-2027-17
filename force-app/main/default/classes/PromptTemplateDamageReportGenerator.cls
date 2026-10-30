/**
 * Calls the Prompt Builder template Damage_Report_Summary (TDD 7.6) through the Einstein LLM Connect API.
 * Template inputs: Vehicle (Vehicle__c), Pickup (Inspection__c), Return (Inspection__c).
 * Requires Einstein generative AI to be enabled; callers fall back to RuleBasedDamageReportGenerator on failure.
 */
public with sharing class PromptTemplateDamageReportGenerator implements DamageReportGenerator {
    public static final String TEMPLATE = 'Damage_Report_Summary';

    public String generate(Vehicle__c vehicle, Inspection__c pickup, Inspection__c returnInspection) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:Vehicle' => wrap(vehicle.Id),
            'Input:Pickup' => wrap(pickup.Id),
            'Input:Return' => wrap(returnInspection.Id)
        };
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
            TEMPLATE,
            input
        );
        if (output == null || output.generations == null || output.generations.isEmpty() ||
            String.isBlank(output.generations[0].text)) {
            throw new InspectionException('The AI service returned an empty damage report.');
        }
        return output.generations[0].text.trim();
    }

    private static ConnectApi.WrappedValue wrap(Id recordId) {
        ConnectApi.WrappedValue value = new ConnectApi.WrappedValue();
        value.value = new Map<String, String>{ 'id' => recordId };
        return value;
    }
}