/**
 * Generates the pickup-vs-return damage report (TDD 7.6). Implementations:
 *  - PromptTemplateDamageReportGenerator – Prompt Builder template Damage_Report_Summary (default)
 *  - RuleBasedDamageReportGenerator      – deterministic fallback when generative AI is unavailable
 */
public interface DamageReportGenerator {
    String generate(Vehicle__c vehicle, Inspection__c pickup, Inspection__c returnInspection);
}