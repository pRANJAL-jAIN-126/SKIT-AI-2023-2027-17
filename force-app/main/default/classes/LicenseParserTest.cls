/**
 * LicenseParser, NameMatcher, DataMasking and OcrResult – TDD 9.5 parser rules, R5, NFR-03.
 */
@IsTest
private class LicenseParserTest {
    private static OcrResult text(String t) {
        OcrResult r = new OcrResult();
        r.text = t;
        return r;
    }

    @IsTest
    static void parsesLabelledLicenceText() {
        LicenseParser.ParsedLicense p = LicenseParser.parse(text(TestDataFactory.licenceText('Rahul Sharma', 'RJ14 2015 0012345', '15-05-1990', '14-05-2040')));
        Assert.areEqual('RJ1420150012345', p.licenseNo, 'spaces stripped');
        Assert.areEqual(Date.newInstance(1990, 5, 15), p.dob);
        Assert.areEqual(Date.newInstance(2040, 5, 14), p.expiry, 'Validity (NT) date is the expiry, not the issue date');
        Assert.areEqual('RAHUL SHARMA', p.name, 'S/D/W of line ignored');
        Assert.isNull(p.confidence);
        Assert.isTrue(LicenseParser.isValidFormat(p.licenseNo));
    }

    @IsTest
    static void unlabelledDatesUseEarliestAndLatest() {
        LicenseParser.ParsedLicense p = LicenseParser.parse(text('NAME RAHUL SHARMA\n01/02/2030 15/05/1990 10/01/2015 RJ-14-2015-0012345'));
        Assert.areEqual(Date.newInstance(1990, 5, 15), p.dob);
        Assert.areEqual(Date.newInstance(2030, 2, 1), p.expiry);
        Assert.areEqual('RJ1420150012345', p.licenseNo);
    }

    @IsTest
    static void labelFallbackForNonStandardNumber() {
        LicenseParser.ParsedLicense p = LicenseParser.parse(text('DL NO: MH12 99 1234\nName:\nAnita Desai\nDOB: 01-01-1985 Valid Till: 01-01-2035'));
        Assert.areEqual('MH12991234', p.licenseNo);
        Assert.isFalse(LicenseParser.isValidFormat(p.licenseNo), 'R2 will send this to review');
        Assert.areEqual('ANITA DESAI', p.name, 'name on the following line');
    }

    @IsTest
    static void structuredFieldsWinOverText() {
        OcrResult r = OcrResult.fromJson(
            '{"lines":["random text"],"fields":{"name":"Rahul Sharma","dob":"1990-05-15","licenseNumber":"RJ14-2015-0012345","expiry":"14/05/2040"},' +
            '"confidence":{"name":0.95,"licenseNumber":92}}'
        );
        LicenseParser.ParsedLicense p = LicenseParser.parse(r);
        Assert.areEqual('Rahul Sharma', p.name);
        Assert.areEqual(Date.newInstance(1990, 5, 15), p.dob);
        Assert.areEqual('RJ1420150012345', p.licenseNo);
        Assert.areEqual(Date.newInstance(2040, 5, 14), p.expiry);
        Assert.areEqual(0.92, p.confidence, 'lowest confidence, percentages normalised');
    }

    @IsTest
    static void unreadableInput() {
        LicenseParser.ParsedLicense p = LicenseParser.parse(text('blurry ### ~~'));
        Assert.isNull(p.licenseNo);
        Assert.isNull(p.dob);
        Assert.isNull(p.name);
        Assert.isNull(LicenseParser.parse(null).name);
        Assert.isNull(LicenseParser.normaliseDate('31-02-2020'), 'invalid calendar date');
        Assert.isNull(LicenseParser.normaliseDate(''));
        try {
            OcrResult.fromJson('not json');
            Assert.fail();
        } catch (KycException e) {
            Assert.areEqual('Could not read the image.', e.getMessage());
        }
        Assert.areEqual(0.7, OcrResult.fromJson('{"text":"x","confidence":0.7}').minConfidence());
    }

    @IsTest
    static void nameMatching() {
        Assert.areEqual(1, NameMatcher.similarity('SHARMA RAHUL', 'Rahul Sharma'), 'order and case ignored');
        Assert.areEqual(1, NameMatcher.similarity('RAHUL K SHARMA', 'Rahul Sharma'), 'initials ignored');
        Assert.isTrue(NameMatcher.similarity('RAHUL KUMAR SHARMA', 'Rahul Sharma') >= 0.8);
        Assert.isTrue(NameMatcher.similarity('RAHUL SHARNA', 'Rahul Sharma') >= 0.8, 'one OCR error tolerated');
        Assert.isTrue(NameMatcher.similarity('PRIYA VERMA', 'Rahul Sharma') < 0.8);
        Assert.areEqual(0, NameMatcher.similarity('', 'Rahul'));
    }

    @IsTest
    static void masking() {
        Assert.areEqual('XXXX2345', DataMasking.maskLicense('RJ14 2015 0012345'));
        Assert.areEqual('****', DataMasking.maskLicense('123'));
        Assert.isNull(DataMasking.maskLicense(null));
        String masked = DataMasking.maskLicenseNumbersIn('{"dl":"RJ14-2015-0012345","phone":"9876543210"}');
        Assert.isFalse(masked.contains('0012345'));
        Assert.isFalse(masked.contains('98765'));
        Assert.isTrue(masked.contains('XXXX2345'));
    }
}