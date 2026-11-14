// Points Vehicle__c.Image_URL__c at the bundled photos in the VehicleImages static resource.
// PREREQUISITE: deploy staticresources/VehicleImages and the vehiclePhoto LWC first.
// Run (after approval):  sf apex run -o CollegeProject -f scripts/apex/update-vehicle-images.apex
//
// Safety: no records are created or deleted. A record is updated only when its registration number AND make/model
// match the expected vehicle, so a renamed or re-purposed record is skipped and reported instead of overwritten.
// VEH-0020 (RJ14-DEMO-0001, Jaipur Demo Branch) is a separate demo Kia Carens, not a duplicate of VEH-0004;
// it previously had no image and gets the same Kia Carens photo.

Map<String, List<String>> expected = new Map<String, List<String>>{
    // registration      => { make, model, file }
    'RJ14 NP 7531' => new List<String>{ 'Maruti', 'Swift', 'maruti-swift.jpg' },
    'RJ14 UV 3344' => new List<String>{ 'Tata', 'Punch', 'tata-punch.jpg' },
    'RJ14 ST 1122' => new List<String>{ 'Hyundai', 'i20', 'hyundai-i20.jpg' },
    'DL01 MN 1010' => new List<String>{ 'Maruti', 'Dzire', 'maruti-dzire.jpg' },
    'RJ14 DE 2233' => new List<String>{ 'Honda', 'Amaze', 'honda-amaze.jpg' },
    'RJ14 BC 9900' => new List<String>{ 'Maruti', 'Ertiga', 'maruti-ertiga.jpg' },
    'DL01 PQ 3030' => new List<String>{ 'Kia', 'Sonet', 'kia-sonet.jpg' },
    'RJ14 LM 8642' => new List<String>{ 'Honda', 'City', 'honda-city.jpg' },
    'RJ14 EF 9101' => new List<String>{ 'Maruti', 'Brezza', 'maruti-brezza.jpg' },
    'DL01 FG 4466' => new List<String>{ 'Hyundai', 'Verna', 'hyundai-verna.jpg' },
    'RJ14 AB 1234' => new List<String>{ 'Kia', 'Seltos', 'kia-seltos.jpg' },
    'DL01 QR 4455' => new List<String>{ 'Tata', 'Nexon EV', 'tata-nexon-ev.jpg' },
    'RJ14 CD 5678' => new List<String>{ 'Hyundai', 'Creta', 'hyundai-creta.jpg' },
    'RJ14 JK 1357' => new List<String>{ 'Kia', 'Carens', 'kia-carens.jpg' },
    'RJ14-DEMO-0001' => new List<String>{ 'Kia', 'Carens', 'kia-carens.jpg' },
    'DL01 HJ 6688' => new List<String>{ 'MG', 'ZS EV', 'mg-zs-ev.jpg' },
    'DL01 RS 5050' => new List<String>{ 'Mahindra', 'Scorpio-N', 'mahindra-scorpio-n.jpg' },
    'RJ14 GH 2468' => new List<String>{ 'Toyota', 'Innova Crysta', 'toyota-innova-crysta.jpg' },
    'RJ14 WX 5566' => new List<String>{ 'Mahindra', 'XUV700', 'mahindra-xuv700.jpg' },
    'RJ14 YZ 7788' => new List<String>{ 'Toyota', 'Fortuner', 'toyota-fortuner.jpg' },
    'DL01 KL 8800' => new List<String>{ 'BMW', '3 Series', 'bmw-3-series.jpg' }
};

List<Vehicle__c> toUpdate = new List<Vehicle__c>();
List<String> skipped = new List<String>();
Set<String> seen = new Set<String>();
for (Vehicle__c v : [
    SELECT Id, Name, Make__c, Model__c, Registration_Number__c, Image_URL__c
    FROM Vehicle__c
    WHERE Registration_Number__c IN :expected.keySet()
]) {
    List<String> e = expected.get(v.Registration_Number__c);
    seen.add(v.Registration_Number__c);
    if (v.Make__c != e[0] || v.Model__c != e[1]) {
        skipped.add(v.Name + ' ' + v.Registration_Number__c + ': is ' + v.Make__c + ' ' + v.Model__c + ', expected ' + e[0] + ' ' + e[1]);
        continue;
    }
    if (v.Image_URL__c != e[2]) {
        toUpdate.add(new Vehicle__c(Id = v.Id, Image_URL__c = e[2]));
    }
}
for (String reg : expected.keySet()) {
    if (!seen.contains(reg)) {
        skipped.add(reg + ': no vehicle with this registration');
    }
}
update toUpdate;
System.debug(LoggingLevel.WARN, 'Vehicle images updated: ' + toUpdate.size());
for (String s : skipped) {
    System.debug(LoggingLevel.WARN, 'SKIPPED ' + s);
}
