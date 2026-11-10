# OCR and KYC Document Verification

## 1. Overview
This module supports OCR-based driving licence document processing
and KYC verification in the Car Rental application.

## 2. Main Apex Components

| Apex Class | Responsibility |
|---|---|
| GenericOcrClient | Generic OCR client integration |
| OcrSpaceClient | OCR.Space client implementation |
| OcrHttp | HTTP communication helper |
| OcrHttpMock | Mock HTTP responses for testing |
| OcrProvider | OCR provider abstraction |
| OcrResult | OCR response representation |
| LicenseParser | Extracts licence details from OCR results |
| NameMatcher | Name matching utility |
| KycService | KYC and licence verification service |
| KycException | KYC-specific exception handling |
| KycServiceTest | KYC service test coverage |
| LicenseParserTest | Licence parser test coverage |

## 3. Licence Information Extraction

The LicenseParser component processes OCR results and extracts:

- Name
- Date of birth
- Driving licence number
- Licence expiry date
- OCR confidence value

It also supports date normalization and driving licence format validation.

## 4. Date Validation

The parser supports the following date formats:

- DD-MM-YYYY
- DD/MM/YYYY
- DD.MM.YYYY
- YYYY-MM-DD

Invalid dates are rejected by the date validation logic.

## 5. Testing

The OCR and KYC module includes dedicated Apex test classes.
HTTP mock functionality can be used to test HTTP integrations
without depending on live external responses.

## 6. Form-2 Mapping

Team member: Pranjal Jain

Assigned user story: OCR API Integration

Assigned period: 11 October – 10 November

Task: Integrate the OCR API for document verification.

## 7. Scope

This documentation describes the OCR and KYC Apex components
identified in the project source tree. Actual provider configuration,
API credentials, deployment settings and runtime behavior should
be verified against the Salesforce org configuration.
