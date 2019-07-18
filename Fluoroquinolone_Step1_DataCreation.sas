/*Copyright (C) 2019 The Regents of the University of Michigan
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see  [https://github.com/CCMRcodes/Fluoroquinolone]
*/


/*authorship: Shirley Wang (inpatient data)
              David Ratz (outpatient data pull)
Date updated: 7/5/2019*/


/***** Step 1: Identify Infection Hospitalization Cohort from VAPD  *****/

%let year=20142017;
libname TEMP 'FOLDER DIRECTORY';

/*From VAPD, get hospitalizations with any antibotics (ABX) use during inpatient stay*/
DATA any_abx (compress=yes);
SET  temp.VAPD_VAtoVA20142017_20190219;
if abx1=1 or abx2=1 or abx3=1 or abx4=1 or abx5=1 or abx6=1 or abx7=1 or abx8=1 or abx9=1 or abx10=1 or 
abx11=1 or abx12=1 or abx13=1 or abx14=1 or abx15=1 or abx16=1 or abx17=1 or abx18=1 or abx19=1 or abx20=1 
    then any_abx=1; 
       else any_abx=0;
if any_abx=1;
any_abx_hosp=1; /*get any abx during hospitalization indicator*/
keep patienticn newadmitdate newdischargedate any_abx any_abx_hosp;
RUN;

PROC SORT DATA=any_abx   nodupkey  OUT=any_abx_hosp; 
BY  patienticn newadmitdate newdischargedate; 
RUN; 

/*get only abx class 7 for fluoroquinolone hosptialization level indicator*/
DATA abx7; 
set temp.vapd_ccs_risk20142017_11262018; 
if abx7=1;
abx7_hosp=1;
keep patienticn newadmitdate newdischargedate abx7 abx7_hosp;
RUN;

PROC SORT DATA=abx7  nodupkey  OUT=abx7_hosp; 
BY  patienticn newadmitdate newdischargedate; 
RUN; 

/*left join abx7_hosp and any_abx_hosp indicators back to VAPD*/
PROC SQL;
	CREATE TABLE  ABX_v1 (compress=yes)  AS 
	SELECT A.*, B.any_abx_hosp, c.abx7_hosp
	FROM  vapd_ccs_risk20142017_11262018   A
	LEFT JOIN any_abx_hosp  B ON A.patienticn =B.patienticn and a.newadmitdate=b.newadmitdate and a.newdischargedate =b.newdischargedate  
	LEFT JOIN abx7_hosp  C ON A.patienticn =C.patienticn and a.newadmitdate=C.newadmitdate and a.newdischargedate =C.newdischargedate;
QUIT;

/*get cohort on Any ABX use for the last 3 days of hospitalization, use this cohort to pull in outpatient meds below*/
DATA temp.any_abx_cohort_12142018  (compress=yes); 
SET  ABX_v1 (keep=patienticn sta3n sta6a specialty cdw_admitdatetime cdw_dischargedatetime newadmitdate newdischargedate datevalue abx1-abx20 any_abx_hosp abx7_hosp);
days_prior_discharge=(newdischargedate-datevalue)+1;
if (abx1=1 or abx2=1 or abx3=1 or abx4=1 or abx5=1 or abx6=1 or abx7=1 or abx8=1 or abx9=1 or abx10=1 or 
abx11=1 or abx12=1 or abx13=1 or abx14=1 or abx15=1 or abx16=1 or abx17=1 or abx18=1 or abx19=1 or abx20=1)
AND days_prior_discharge <=2;
RUN;

/*The VAPD has only ABX class indicators, need specific Med_route back on patient-facilty-day. So pull and use the inpatient ABX pull from
the VAPD codes folder on Github*/
/*left join ABX meds to VA to VA transfer VAPD dataset*/
/*only keep Moxifloxacin, Levofloxacin & ciprofloxacin*/
DATA Levo_cipro_moxi (compress=yes); 
SET  pharm.all_abx_07132018;
if med_route in ('Levofloxacin_IV','Levofloxacin_PO','Ciprofloxacin_PO','Ciprofloxacin_IV','Moxifloxacin_IV','Moxifloxacin_PO');
RUN;

PROC FREQ DATA=Levo_cipro_moxi  order=freq;
TABLE  med_route;
RUN;

/*transpose from long to wide from*/
PROC TRANSPOSE DATA=Levo_cipro_moxi OUT=Levo_cipro_moxi_trans (DROP=_NAME_ )  PREFIX= abx_med_  ; 
BY PatientICN actiondate;
VAR med_route;
RUN;

PROC FREQ DATA=Levo_cipro_moxi_trans order=freq;
TABLE abx_med_4 abx_med_3;
RUN;

/*left join to VAPD dataset*/
PROC SQL;
	CREATE TABLE temp.FlurABX_20142017_20190220  (compress=yes)  AS 
	SELECT A.*, B.*
	FROM  temp.VAPD_VAtoVA20142017_20190219  A
	LEFT JOIN Levo_cipro_moxi_trans  B ON A.PatientICN =B.PatientICN and a.datevalue=b.actiondate;
QUIT;


/***********************************************************************************************************************************/
/*Use temp.any_abx_cohort_12142018 to pull outpatient medications*/
 
/**** PULL OUTPATIENT MEDICATIONS ****/
ods html close; ods html;

libname dbs2 oledb provider=sqloledb
datasource="*****"
properties=('INITIAL CATALOG' = STUDYNAME_INSERT_HERE 'INTEGRATED SECURITY'=SSPI)
schema="src";

libname dflt oledb provider=sqloledb
datasource="*****"
properties=('INITIAL CATALOG' = STUDYNAME_INSERT_HERE 'INTEGRATED SECURITY'=SSPI)
schema="dflt";

/* upload data temp.any_abx_cohort_12142018 to SQL to pull meds */
proc sql;
create table sql_cohort as 
select distinct PatientSID, sta3n, sta6a, cdw_admitdatetime,cdw_dischargedatetime,new_admitdate2,new_dischargedate2,patienticn 
from temp.any_abx_cohort_12142018; 
quit;

data dflt.abx_cohort_w_dates_sid_012419; 
set sql_cohort; 
run;

data abx_cohort_dates; 
set temp.any_abx_cohort_12142018; 
run;

data abx_cohort_dates_old; 
set temp.Any_Abx__Cohort; 
run;

proc sql; 
create table look3 as 
select distinct patienticn 
from abx_cohort_dates_old; 
quit;

proc sql; 
create table look4 as 
select distinct patienticn 
from abx_cohort_dates; 
quit;

proc sql; 
create table abx_cohort_dates_uniq as 
select distinct patientsid, patienticn, sta3n, sta6a, cdw_admitdatetime, cdw_dischargedatetime, newadmitdate as admitday, 
             newdischargedate as disday, any_abx_hosp, abx_fluoroquinolone 
from abx_cohort_dates; 
quit;

data look; 
set dflt.abx_cohort_w_dates_SID_num; 
run;

proc sql; 
create table look2 as 
select distinct patienticn 
from look; 
quit;

data dflt.abx_cohort_w_dates_SID_num_11302018; 
set abx_cohort_dates_uniq; 
run;

data dis_meds; 
set dflt.abx_cohort_dis_meds_012419_w_rt2; 
dis_day=input(new_dischargedate2,mmddyy10.); 
format dis_day mmddyy10.;  
run;

proc freq data=dis_meds; 
table drugnamewithoutdose; 
run;

data miss_dis_meds; 
set dis_meds; 
where drugnamewithoutdose=''; 
run;

data miss_dis_med_name; 
set dis_meds; 
where drugnamewithoutdose='*Missing*'; 
run;

proc freq data=abx_cohort_dates;
table year;
run;

libname dim oledb provider=sqloledb
datasource="******"
properties=('INITIAL CATALOG' = CDWWORK 'INTEGRATED SECURITY'=SSPI)
schema="dim";

data dis_meds_abx; 
set dis_meds;
IF index(drugnamewithoutdose,'PENICILLIN')>0 |           index(drugnamewithoutdose,'AMOXICILLIN')>0 |             index(drugnamewithoutdose,'AMOXICILLIN/CLAVULANATE')>0 |
index(drugnamewithoutdose,'TICARCILLIN/CLAVULANATE')>0 | index(drugnamewithoutdose,'AMPICILLIN/SULBACTAM')>0 |    index(drugnamewithoutdose,'AMPICILLIN')>0 |
index(drugnamewithoutdose,'NAFCILLIN')>0 |               index(drugnamewithoutdose,'PIPERACILLIN')>0 |            index(drugnamewithoutdose,'DICLOXACILLIN')>0 |
index(drugnamewithoutdose,'OXACILLIN')>0 |               index(drugnamewithoutdose,'PIPERACILLIN/TAZOBACTAM')>0 | index(drugnamewithoutdose,'CEFAZOLIN')>0 |
index(drugnamewithoutdose,'CEPHALEXIN')>0 |              index(drugnamewithoutdose,'CEFADROXIL')>0 |              index(drugnamewithoutdose,'CEFOXITIN')>0 |
index(drugnamewithoutdose,'CEFUROXIME')>0 |              index(drugnamewithoutdose,'CEFACLOR')>0 |                index(drugnamewithoutdose,'CEFPROZIL')>0 |
index(drugnamewithoutdose,'CEFOTETAN')>0 |               index(drugnamewithoutdose,'CEFIXIME')>0 |                index(drugnamewithoutdose,'CEFTIBUTEN')>0 |
index(drugnamewithoutdose,'CEFTRIAXONE')>0 |             index(drugnamewithoutdose,'CEFTAZIDIME')>0 |             index(drugnamewithoutdose,'CEFDINIR')>0 |
index(drugnamewithoutdose,'CEFOTAXIME')>0 |              index(drugnamewithoutdose,'CEFTAZIDIME/AVIBACTAM')>0 |   index(drugnamewithoutdose,'CEFPODOXIME')>0 |
index(drugnamewithoutdose,'CEFEPIME')>0 |                index(drugnamewithoutdose,'OFLOXACIN')>0 |               index(drugnamewithoutdose,'CIPROFLOXACIN')>0 |
index(drugnamewithoutdose,'LEVOFLOXACIN')>0 |            index(drugnamewithoutdose,'MOXIFLOXACIN')>0 |            index(drugnamewithoutdose,'NORFLOXACIN')>0 |
index(drugnamewithoutdose,'TELAVANCIN')>0 |              index(drugnamewithoutdose,'DALBAVANCIN')>0 |             index(drugnamewithoutdose,'ORITAVANCIN')>0 |
index(drugnamewithoutdose,'VANCOMYCIN')>0 |              index(drugnamewithoutdose,'FIDAXOMICIN')>0 |             index(drugnamewithoutdose,'ACYCLOVIR')>0 |
index(drugnamewithoutdose,'PERAMIVIR')>0 |               index(drugnamewithoutdose,'GANCICLOVIR')>0 |             index(drugnamewithoutdose,'FOSCARNET')>0 |
index(drugnamewithoutdose,'AZITHROMYCIN')>0 |            index(drugnamewithoutdose,'METRONIDAZOLE')>0 |           index(drugnamewithoutdose,'TRIMETHOPRIM/SULFAMETHOXAZOLE')>0 |
index(drugnamewithoutdose,'SULFAMETHOXAZOLE')>0 |        index(drugnamewithoutdose,'SULFADIAZINE')>0 |            index(drugnamewithoutdose,'TRIMETHOPRIM')>0 |
index(drugnamewithoutdose,'TETRACYCLINE')>0 |            index(drugnamewithoutdose,'TRIMETHOPRIM/SULFAMETHOXAZOLE')>0 | index(drugnamewithoutdose,'FLUCONAZOLE')>0 |
index(drugnamewithoutdose,'MICAFUNGIN')>0 |              index(drugnamewithoutdose,'VORICONAZOLE')>0 |            index(drugnamewithoutdose,'POSACONAZOLE')>0 |
index(drugnamewithoutdose,'ITRACONAZOLE')>0 |            index(drugnamewithoutdose,'AMPHOTERICIN B')>0 |          index(drugnamewithoutdose,'CASPOFUNGIN')>0 |
index(drugnamewithoutdose,'ANIDULAFUNGIN')>0 |           index(drugnamewithoutdose,'AZTREONAM')>0 |               index(drugnamewithoutdose,'CLINDAMYCIN')>0 |
index(drugnamewithoutdose,'DAPTOMYCIN')>0 |              index(drugnamewithoutdose,'TIGECYCLINE')>0 |             index(drugnamewithoutdose,'LINEZOLID')>0 |
index(drugnamewithoutdose,'CEFTAROLINE')>0 |             index(drugnamewithoutdose,'TEDIZOLID')>0 |               index(drugnamewithoutdose,'COLISTIN')>0 |
index(drugnamewithoutdose,'COLISTIMETHATE')>0 |          index(drugnamewithoutdose,'POLYMYXIN B')>0 |             index(drugnamewithoutdose,'CEFTAROLINE')>0 |
index(drugnamewithoutdose,'CEFTOLOZANE/TAZOBACTAM')>0 |  index(drugnamewithoutdose,'QUINUPRISTIN/DALFOPRISTIN')>0 | index(drugnamewithoutdose,'GENTAMICIN')>0 |
index(drugnamewithoutdose,'AMIKACIN')>0 |                index(drugnamewithoutdose,'STREPTOMYCIN')>0 |            index(drugnamewithoutdose,'TOBRAMYCIN')>0 |
index(drugnamewithoutdose,'DOXYCYCLINE')>0 |             index(drugnamewithoutdose,'MINOCYCLINE')>0 |             index(drugnamewithoutdose,'NITROFURANTOIN')>0 |
index(drugnamewithoutdose,'FOSFOMYCIN')>0 |
index(LocalDrugNameWithDose,'PENICILLIN')>0 |              index(LocalDrugNameWithDose,'AMOXICILLIN')>0 |             index(LocalDrugNameWithDose,'AMOXICILLIN/CLAVULANATE')>0 |
index(LocalDrugNameWithDose,'TICARCILLIN/CLAVULANATE')>0 | index(LocalDrugNameWithDose,'AMPICILLIN/SULBACTAM')>0 |    index(LocalDrugNameWithDose,'AMPICILLIN')>0 |
index(LocalDrugNameWithDose,'NAFCILLIN')>0 |               index(LocalDrugNameWithDose,'PIPERACILLIN')>0 |            index(LocalDrugNameWithDose,'DICLOXACILLIN')>0 |
index(LocalDrugNameWithDose,'OXACILLIN')>0 |               index(LocalDrugNameWithDose,'PIPERACILLIN/TAZOBACTAM')>0 | index(LocalDrugNameWithDose,'CEFAZOLIN')>0 |
index(LocalDrugNameWithDose,'CEPHALEXIN')>0 |              index(LocalDrugNameWithDose,'CEFADROXIL')>0 |              index(LocalDrugNameWithDose,'CEFOXITIN')>0 |
index(LocalDrugNameWithDose,'CEFUROXIME')>0 |              index(LocalDrugNameWithDose,'CEFACLOR')>0 |                index(LocalDrugNameWithDose,'CEFPROZIL')>0 |
index(LocalDrugNameWithDose,'CEFOTETAN')>0 |               index(LocalDrugNameWithDose,'CEFIXIME')>0 |                index(LocalDrugNameWithDose,'CEFTIBUTEN')>0 |
index(LocalDrugNameWithDose,'CEFTRIAXONE')>0 |             index(LocalDrugNameWithDose,'CEFTAZIDIME')>0 |             index(LocalDrugNameWithDose,'CEFDINIR')>0 |
index(LocalDrugNameWithDose,'CEFOTAXIME')>0 |              index(LocalDrugNameWithDose,'CEFTAZIDIME/AVIBACTAM')>0 |   index(LocalDrugNameWithDose,'CEFPODOXIME')>0 |
index(LocalDrugNameWithDose,'CEFEPIME')>0 |                index(LocalDrugNameWithDose,'OFLOXACIN')>0 |               index(LocalDrugNameWithDose,'CIPROFLOXACIN')>0 |
index(LocalDrugNameWithDose,'LEVOFLOXACIN')>0 |            index(LocalDrugNameWithDose,'MOXIFLOXACIN')>0 |            index(LocalDrugNameWithDose,'NORFLOXACIN')>0 |
index(LocalDrugNameWithDose,'TELAVANCIN')>0 |              index(LocalDrugNameWithDose,'DALBAVANCIN')>0 |             index(LocalDrugNameWithDose,'ORITAVANCIN')>0 |
index(LocalDrugNameWithDose,'VANCOMYCIN')>0 |              index(LocalDrugNameWithDose,'FIDAXOMICIN')>0 |             index(LocalDrugNameWithDose,'ACYCLOVIR')>0 |
index(LocalDrugNameWithDose,'PERAMIVIR')>0 |               index(LocalDrugNameWithDose,'GANCICLOVIR')>0 |             index(LocalDrugNameWithDose,'FOSCARNET')>0 |
index(LocalDrugNameWithDose,'AZITHROMYCIN')>0 |            index(LocalDrugNameWithDose,'METRONIDAZOLE')>0 |           index(LocalDrugNameWithDose,'TRIMETHOPRIM/SULFAMETHOXAZOLE')>0 |
index(LocalDrugNameWithDose,'SULFAMETHOXAZOLE')>0 |        index(LocalDrugNameWithDose,'SULFADIAZINE')>0 |            index(LocalDrugNameWithDose,'TRIMETHOPRIM')>0 |
index(LocalDrugNameWithDose,'TETRACYCLINE')>0 |            index(LocalDrugNameWithDose,'TRIMETHOPRIM/SULFAMETHOXAZOLE')>0 | index(LocalDrugNameWithDose,'FLUCONAZOLE')>0 |
index(LocalDrugNameWithDose,'MICAFUNGIN')>0 |              index(LocalDrugNameWithDose,'VORICONAZOLE')>0 |            index(LocalDrugNameWithDose,'POSACONAZOLE')>0 |
index(LocalDrugNameWithDose,'ITRACONAZOLE')>0 |            index(LocalDrugNameWithDose,'AMPHOTERICIN B')>0 |          index(LocalDrugNameWithDose,'CASPOFUNGIN')>0 |
index(LocalDrugNameWithDose,'ANIDULAFUNGIN')>0 |           index(LocalDrugNameWithDose,'AZTREONAM')>0 |               index(LocalDrugNameWithDose,'CLINDAMYCIN')>0 |
index(LocalDrugNameWithDose,'DAPTOMYCIN')>0 |              index(LocalDrugNameWithDose,'TIGECYCLINE')>0 |             index(LocalDrugNameWithDose,'LINEZOLID')>0 |
index(LocalDrugNameWithDose,'CEFTAROLINE')>0 |             index(LocalDrugNameWithDose,'TEDIZOLID')>0 |               index(LocalDrugNameWithDose,'COLISTIN')>0 |
index(LocalDrugNameWithDose,'COLISTIMETHATE')>0 |          index(LocalDrugNameWithDose,'POLYMYXIN B')>0 |             index(LocalDrugNameWithDose,'CEFTAROLINE')>0 |
index(LocalDrugNameWithDose,'CEFTOLOZANE/TAZOBACTAM')>0 |  index(LocalDrugNameWithDose,'QUINUPRISTIN/DALFOPRISTIN')>0 | index(LocalDrugNameWithDose,'GENTAMICIN')>0 |
index(LocalDrugNameWithDose,'AMIKACIN')>0 |                index(LocalDrugNameWithDose,'STREPTOMYCIN')>0 |            index(LocalDrugNameWithDose,'TOBRAMYCIN')>0 |
index(LocalDrugNameWithDose,'DOXYCYCLINE')>0 |             index(LocalDrugNameWithDose,'MINOCYCLINE')>0 |             index(LocalDrugNameWithDose,'NITROFURANTOIN')>0 |
index(LocalDrugNameWithDose,'FOSFOMYCIN')>0  then output;   
run;

data dropped_meds; 
set dis_meds_abx;
if index(LocalDrugNameWithDose, 'OINT')>0 |         index(LocalDrugNameWithDose, 'OPHTH SOLN')>0 | index(LocalDrugNameWithDose, 'OPTH SOLN')>0 |
index(LocalDrugNameWithDose, 'OPH SOLN')>0 |        index(LocalDrugNameWithDose, 'TOP SOLN')>0 |   index(LocalDrugNameWithDose, 'OPTHAL SOLN')>0 | 
index(LocalDrugNameWithDose, 'SOLN,OPH')>0 |        index(LocalDrugNameWithDose, 'OPHT SOLN')>0 |  index(LocalDrugNameWithDose, 'OPHTHALMIC SOLN')>0 |  
index(LocalDrugNameWithDose, 'OPTHALMIC SOLN')>0 |  index(LocalDrugNameWithDose, 'otic soln')>0 |  index(LocalDrugNameWithDose, 'OPHTH SOL')>0 |
index(LocalDrugNameWithDose, 'OPH SOL')>0 |         index(LocalDrugNameWithDose, 'OPHTH.SOL')>0 |  index(LocalDrugNameWithDose, 'SUSP,OPH')>0 |
index(LocalDrugNameWithDose, 'OPH SUSP')>0 |        index(LocalDrugNameWithDose, 'EYE SUSP')>0 |   index(LocalDrugNameWithDose, 'OPHTH SUSP')>0 |
index(LocalDrugNameWithDose, 'OPH SUS')>0 |         index(LocalDrugNameWithDose, 'GEL')>0 |        index(LocalDrugNameWithDose, 'LOTION')>0 |
index(LocalDrugNameWithDose, 'CREAM')>0 |           index(LocalDrugNameWithDose, 'OTIC')>0 |       index(LocalDrugNameWithDose, 'TOP PLEDGET')>0 |
index(LocalDrugNameWithDose, 'TOP SWAB')>0 |        index(LocalDrugNameWithDose, 'SWAB,TOP')>0 |   index(LocalDrugNameWithDose, 'TOP LOT')>0 |
index(LocalDrugNameWithDose, 'ONT,OPH')>0 |
index(LocalDrugNameWithDose, 'FLUCONAZOLE')>0 |    index(LocalDrugNameWithDose, 'ITRACONAZOLE')>0 | index(LocalDrugNameWithDose, 'POSACONAZOLE')>0 |
index(LocalDrugNameWithDose, 'VALACYCLOVIR')>0 |   index(LocalDrugNameWithDose, 'VORICONAZOLE')>0 | index(LocalDrugNameWithDose, 'ValACYClovir')>0 |
index(LocalDrugNameWithDose, 'PEN G POTAS PAR FOR INJ, 20 MU')>0 |           index(LocalDrugNameWithDose, 'OFLOXACIN 0.3% OS (PER ML)')>0 |
index(LocalDrugNameWithDose, 'BACITRACIN/POLYMYXIN OO, 3.5GM')>0 |           index(LocalDrugNameWithDose, 'CIPROFLOXACIN HCL 0.3% OS')>0 |
index(LocalDrugNameWithDose, 'CPD VANCOMYCIN 25MG/ML IN HYPOTEARS')>0 |      index(LocalDrugNameWithDose, 'DEXAMETHASONE/TOBRAMYCIN OS')>0 |
index(LocalDrugNameWithDose, 'GENTAMICIN 480MG/L H2O W/NAHCO3 IRR--1L')>0 |  index(LocalDrugNameWithDose, 'INV-VANCOMYCIN 125MG/PLACEBO 14-013 F955')>0 |
index(LocalDrugNameWithDose, 'TOBRAMYCIN 300MG/5ML ORAL INHL SOLN 5ML')>0 |  index(LocalDrugNameWithDose, 'TOBRAMYCIN 300MG/5ML PF SOLN,INHL,ORAL')>0 |
index(LocalDrugNameWithDose, 'TOBRAMYCIN 300MG/5ML SOLN, INH, ORAL 5ML')>0 | index(LocalDrugNameWithDose, 'TOBRAMYCIN 300MG/7.5ML ORAL INH SOL SYR')>0 |
index(LocalDrugNameWithDose, 'TRIMETH/SULFAMETHOX SUSP EACH ML')>0 |         index(LocalDrugNameWithDose, 'TRIMETH/SULFAMETHOX 40-200/5ML SUSP (ML)')>0 |
index(LocalDrugNameWithDose, 'VANCOMYCIN 1GM/200ML ISO-OSMOTIC PREMIX')>0 |  index(LocalDrugNameWithDose, 'SILVER SULFADIAZINE 1% CR, (PER GM)')>0 |
index(LocalDrugNameWithDose, 'SILVER SULFADIAZINE 1% CR. 20G TUBE')>0 |      index(LocalDrugNameWithDose, 'SILVER SULFADIAZINE 1% CR 400GM')>0  then output;

if MedicationRoute in ('AFFECTED AREA','AFFECTED EAR','AFFECTED EAR(S)','AFFECTED EYE','AFFECTED EYE(S)','AS DIRECTED','BOTH EARS','BOTH EYES','DEEP IM','EACH EYE','EAR','EXTERNAL',
'EXTERNALLY','EYE','IN EACH EYE','INTRAVITREAL','IRRIGATION','LEFT EYE','MISCELLANEOUS','NONE','OPERATED EYE','OPHTHALMIC','OPHTHALMIC (BOTH)','OPHTHALMIC (DROPS)','OPHTHALMIC (OINT)',
'OPHTHALMIC BOTH','OPHTHALMIC TOPICAL','OPHTHALMIC<OU>','OPTHALMIC','OTHER','OTIC','OTIC (BOTH EARS)','OTIC (EAR)','OTIC (LEFT EAR)','RIGHT EAR','RIGHT EYE','SUBJUNCTIVAL',
'SWISH AND SPIT','TO EYE(S)','TOPICAL','TOPICAL CREAM','TOPICAL DERMAL','TOPICAL LOTION','TOPICAL MISCELLANEOUS','TOPICAL OINTMENT','TOPICAL OPHTHALMIC','TOPICAL SOLUTION',
'TOPICALLY','TOPICALLY TO AFFECTED AREA','URETHRAL','VAGINAL','VAGINALLY','zzWHICH EAR') then delete;

if UnitDoseMedicationRoute in ('AFFECTED EYE(S)','BOTH EARS','BOTH EYES','EACH EYE','MISCELLANEOUS','OPHTHALMIC','OPHTHALMIC (BOTH)','OPHTHALMIC TOPICAL','OPTHALMIC',
'OTIC','TOPICAL','TOPICAL OPHTHALMIC','TOPICALLY','VAGINAL TOPICAL','ZZOPHTHALMIC OINTMENT','ZZOPHTHALMIC SPACE','ZZOPHTHALMIC SUSPENSION','ZZOPTHALMIC','ZZOTIC','ZZZOPTHALMIC',
'ZZZZZZZZ') then delete;
run;

data dis_meds_abx2; 
set dis_meds_abx;
if index(LocalDrugNameWithDose, 'OINT')>0 |         index(LocalDrugNameWithDose, 'OPHTH SOLN')>0 | index(LocalDrugNameWithDose, 'OPTH SOLN')>0 |
index(LocalDrugNameWithDose, 'OPH SOLN')>0 |        index(LocalDrugNameWithDose, 'TOP SOLN')>0 |   index(LocalDrugNameWithDose, 'OPTHAL SOLN')>0 | 
index(LocalDrugNameWithDose, 'SOLN,OPH')>0 |        index(LocalDrugNameWithDose, 'OPHT SOLN')>0 |  index(LocalDrugNameWithDose, 'OPHTHALMIC SOLN')>0 |  
index(LocalDrugNameWithDose, 'OPTHALMIC SOLN')>0 |  index(LocalDrugNameWithDose, 'otic soln')>0 |  index(LocalDrugNameWithDose, 'OPHTH SOL')>0 |
index(LocalDrugNameWithDose, 'OPH SOL')>0 |         index(LocalDrugNameWithDose, 'OPHTH.SOL')>0 |  index(LocalDrugNameWithDose, 'SUSP,OPH')>0 |
index(LocalDrugNameWithDose, 'OPH SUSP')>0 |        index(LocalDrugNameWithDose, 'EYE SUSP')>0 |   index(LocalDrugNameWithDose, 'OPHTH SUSP')>0 |
index(LocalDrugNameWithDose, 'OPH SUS')>0 |         index(LocalDrugNameWithDose, 'GEL')>0 |        index(LocalDrugNameWithDose, 'LOTION')>0 |
index(LocalDrugNameWithDose, 'CREAM')>0 |           index(LocalDrugNameWithDose, 'OTIC')>0 |       index(LocalDrugNameWithDose, 'TOP PLEDGET')>0 |
index(LocalDrugNameWithDose, 'TOP SWAB')>0 |        index(LocalDrugNameWithDose, 'SWAB,TOP')>0 |   index(LocalDrugNameWithDose, 'TOP LOT')>0 |
index(LocalDrugNameWithDose, 'ONT,OPH')>0 |
index(LocalDrugNameWithDose, 'FLUCONAZOLE')>0 |    index(LocalDrugNameWithDose, 'ITRACONAZOLE')>0 | index(LocalDrugNameWithDose, 'POSACONAZOLE')>0 |
index(LocalDrugNameWithDose, 'VALACYCLOVIR')>0 |   index(LocalDrugNameWithDose, 'VORICONAZOLE')>0 | index(LocalDrugNameWithDose, 'ValACYClovir')>0 |
index(LocalDrugNameWithDose, 'PEN G POTAS PAR FOR INJ, 20 MU')>0 |           index(LocalDrugNameWithDose, 'OFLOXACIN 0.3% OS (PER ML)')>0 |
index(LocalDrugNameWithDose, 'BACITRACIN/POLYMYXIN OO, 3.5GM')>0 |           index(LocalDrugNameWithDose, 'CIPROFLOXACIN HCL 0.3% OS')>0 |
index(LocalDrugNameWithDose, 'CPD VANCOMYCIN 25MG/ML IN HYPOTEARS')>0 |      index(LocalDrugNameWithDose, 'DEXAMETHASONE/TOBRAMYCIN OS')>0 |
index(LocalDrugNameWithDose, 'GENTAMICIN 480MG/L H2O W/NAHCO3 IRR--1L')>0 |  index(LocalDrugNameWithDose, 'INV-VANCOMYCIN 125MG/PLACEBO 14-013 F955')>0 |
index(LocalDrugNameWithDose, 'TOBRAMYCIN 300MG/5ML ORAL INHL SOLN 5ML')>0 |  index(LocalDrugNameWithDose, 'TOBRAMYCIN 300MG/5ML PF SOLN,INHL,ORAL')>0 |
index(LocalDrugNameWithDose, 'TOBRAMYCIN 300MG/5ML SOLN, INH, ORAL 5ML')>0 | index(LocalDrugNameWithDose, 'TOBRAMYCIN 300MG/7.5ML ORAL INH SOL SYR')>0 |
index(LocalDrugNameWithDose, 'TRIMETH/SULFAMETHOX SUSP EACH ML')>0 |         index(LocalDrugNameWithDose, 'TRIMETH/SULFAMETHOX 40-200/5ML SUSP (ML)')>0 |
index(LocalDrugNameWithDose, 'VANCOMYCIN 1GM/200ML ISO-OSMOTIC PREMIX')>0 |  index(LocalDrugNameWithDose, 'SILVER SULFADIAZINE 1% CR, (PER GM)')>0 |
index(LocalDrugNameWithDose, 'SILVER SULFADIAZINE 1% CR. 20G TUBE')>0 |      index(LocalDrugNameWithDose, 'SILVER SULFADIAZINE 1% CR 400GM')>0  |
MedicationRoute in ('AFFECTED AREA','AFFECTED EAR','AFFECTED EAR(S)','AFFECTED EYE','AFFECTED EYE(S)','AS DIRECTED','BOTH EARS','BOTH EYES','DEEP IM','EACH EYE','EAR','EXTERNAL',
'EXTERNALLY','EYE','IN EACH EYE','INTRAVITREAL','IRRIGATION','LEFT EYE','MISCELLANEOUS','NONE','OPERATED EYE','OPHTHALMIC','OPHTHALMIC (BOTH)','OPHTHALMIC (DROPS)','OPHTHALMIC (OINT)',
'OPHTHALMIC BOTH','OPHTHALMIC TOPICAL','OPHTHALMIC<OU>','OPTHALMIC','OTHER','OTIC','OTIC (BOTH EARS)','OTIC (EAR)','OTIC (LEFT EAR)','RIGHT EAR','RIGHT EYE','SUBJUNCTIVAL',
'SWISH AND SPIT','TO EYE(S)','TOPICAL','TOPICAL CREAM','TOPICAL DERMAL','TOPICAL LOTION','TOPICAL MISCELLANEOUS','TOPICAL OINTMENT','TOPICAL OPHTHALMIC','TOPICAL SOLUTION',
'TOPICALLY','TOPICALLY TO AFFECTED AREA','URETHRAL','VAGINAL','VAGINALLY','zzWHICH EAR') |
UnitDoseMedicationRoute in ('AFFECTED EYE(S)','BOTH EARS','BOTH EYES','EACH EYE','MISCELLANEOUS','OPHTHALMIC','OPHTHALMIC (BOTH)','OPHTHALMIC TOPICAL','OPTHALMIC',
'OTIC','TOPICAL','TOPICAL OPHTHALMIC','TOPICALLY','VAGINAL TOPICAL','ZZOPHTHALMIC OINTMENT','ZZOPHTHALMIC SPACE','ZZOPHTHALMIC SUSPENSION','ZZOPTHALMIC','ZZOTIC','ZZZOPTHALMIC',
'ZZZZZZZZ') then delete;
run;

data TEMP.discharge_meds013119; 
set dis_meds_abx2; 
run;

/*left join outpat meds data*/
/*make a copy of temp.Discharge_meds013119*/
DATA dismeds_copy (compress=yes rename=patienticn2=patienticn); 
SET TEMP.Discharge_meds013119;
patienticn2 = input(patienticn, 10.);/*change patienticn into numeric*/ 
/*change new_admitdate2 and new_dischargedate2 to numeric*/
admitdate_v2=input(new_admitdate2,mmddyy10.);
dischargedate_v2=input(new_dischargedate2,mmddyy10.);
drop patienticn;
format admitdate_v2 mmddyy10. dischargedate_v2 mmddyy10.;
RUN;

PROC SORT DATA=dismeds_copy  nodupkey  OUT=dismeds_copy2; 
BY  patienticn admitdate_v2 dischargedate_v2;
RUN;

PROC SQL;
	CREATE TABLE temp.FlurABXinpoutpat_20190220  (compress=yes)  AS 
	SELECT A.*, B.RxStatus, b.LocalDrugSID, b.LocalDrugNameWithDose, b.DrugNameWithoutDose, b.PrescribingSta6a,b.IssueDate,b.LoginDate, 
    b.FillDateTime, b.ReleaseDateTime,b.MedicationRoute,b.dis_day,
	b.releaseDate,b.ExpirationDate,b.DispensedDate, b.QtyNumeric,b.DaysSupply, b.PharmacySiteName,b.PharmacyOrderableItem
	FROM   temp.FlurABX_20142017_20190220  A
	LEFT JOIN   dismeds_copy2 B
	ON A.patienticn=B.patienticn and a.new_admitdate2=b.admitdate_v2 and a.new_dischargedate2=b.dischargedate_v2;
QUIT;

PROC CONTENTS DATA= temp.FlurABXinpoutpat_20190220 VARNUM;
RUN;

/*IDENTIFY INFECTION HOSPITALIZATIONS*/
/*Definitions: Infection Hospitalizations = had a culture AND (received 3+ days Abx (inpatient + outpatient) OR received Abx within 1 day of death)*/
DATA inft_hosp (compress=yes);
SET temp.FlurABXinpoutpat_20190220;
if Blood_cult_ind=1 or Other_Micro_ind=1 then culture=1; else culture=0; /*culture_hosp*/
if abx_penicillin=1 or abx_pseudomonal_pcn=1 or abx_1st_gen_cephalosporin=1 or abx_2nd_gen_cephalosporin=1 or abx_3rd_gen_cephalosporin=1 or abx_4th_gen_cephalosporin=1 or 
abx_fluoroquinolone=1 or abx_Vancomycin_IV=1 or abx_Vancomycin_PO=1 or abx_antiviral=1 or
abx_macrolide=1 or abx_flagyl=1 or abx_sulfa=1 or abx_antifungal=1 or abx_Aztreonam_IV=1 or abx_clinda=1 or abx_big_abx=1 or
abx_aminoglycoside=1 or abx_tetracycline=1 or abx_other=1 then any_abx_daily=1; else any_abx_daily=0;  /*abx_daily*/
if ((dod_09212018_pull-1) = datevalue) or (dod_09212018_pull=datevalue) then within_1day_dod=1; else within_1day_dod=0;
if within_1day_dod=1 and any_abx_daily=1 then got_abx_1day_dod_ind=1; else got_abx_1day_dod_ind=0; /*abx within 1 day of death ind*/
label within_1day_dod ='within 1 day of death date indicator'
      got_abx_1day_dod_ind='recieved abx within 1 day of death indicator';
keep patienticn datevalue unique_hosp_count_id new_admitdate3 new_dischargedate3 culture any_abx_daily within_1day_dod got_abx_1day_dod_ind  DaysSupply;
RUN;

/*create culture_hosp indicator*/
DATA culture (compress=yes); 
SET inft_hosp;
if culture=1;
culture_hosp=1;
keep patienticn unique_hosp_count_id culture_hosp;
RUN;

PROC SORT DATA=culture  nodupkey; 
BY  patienticn unique_hosp_count_id culture_hosp;
RUN;

/*got abx within 1 day of death indicator*/
DATA  abx_1day_DOD; 
SET inft_hosp ;
if got_abx_1day_dod_ind=1;
keep patienticn unique_hosp_count_id got_abx_1day_dod_ind;
RUN;

PROC SORT DATA=abx_1day_DOD nodupkey; 
BY  patienticn unique_hosp_count_id got_abx_1day_dod_ind;
RUN;

/*create inpat meds ABX days*/
PROC SQL;
CREATE TABLE sum_inpatabx_days_hosp   (compress=yes) AS  
SELECT *, sum(any_abx_daily) as sum_inpatabx_days_hosp 
FROM inft_hosp
group by unique_hosp_count_id
order by patienticn, unique_hosp_count_id;
QUIT;

/*create outpat meds ABX days*/
DATA outpatabx_days_hosp (compress=yes); 
SET  sum_inpatabx_days_hosp;
if DaysSupply NE .;
keep patienticn unique_hosp_count_id DaysSupply;
RUN;

PROC SQL;
CREATE TABLE outpatabx_days_hosp2 (compress=yes) AS 
SELECT *, max(DaysSupply) as max_outpatabx_days_hosp 
FROM outpatabx_days_hosp
group by unique_hosp_count_id
order by patienticn, unique_hosp_count_id;
QUIT;

PROC SORT DATA=outpatabx_days_hosp2  nodupkey ; 
BY patienticn unique_hosp_count_id max_outpatabx_days_hosp;
RUN;

/*add max_outpatabx_days_hosp variable back to inpat med dataset*/
PROC SQL;
	CREATE TABLE  inoutpat_abx_days (compress=yes)  AS 
	SELECT A.*, B.max_outpatabx_days_hosp as sum_outpatabx_days_hosp 
	FROM   sum_inpatabx_days_hosp  A
	LEFT JOIN outpatabx_days_hosp2  B
	ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

DATA inoutpat_abx_days (compress=yes);
SET inoutpat_abx_days;
if sum_outpatabx_days_hosp=. then sum_outpatabx_days_hosp=0;
RUN;

DATA inoutpat_abx_days2 (compress=yes); 
SET  inoutpat_abx_days;
sum_inoutpat_abx_days_hosp=sum_inpatabx_days_hosp+sum_outpatabx_days_hosp;
RUN;

PROC SORT DATA=inoutpat_abx_days2  nodupkey; 
BY patienticn unique_hosp_count_id;
RUN;

/*left join culture_hosp, got_abx_1day_dod_ind, sum_inpatabx_days_hosp, sum_outpatabx_days_hosp and sum_inoutpat_abx_days_hosp back to temp.FlurABXinpoutpat_20190220*/
PROC SQL;
	CREATE TABLE  FlurABXinpoutpat_V1 (compress=yes)  AS 
	SELECT A.*, B.culture_hosp
	FROM  temp.FlurABXinpoutpat_20190220   A
	LEFT JOIN culture  B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id;
QUIT;

PROC SQL;
	CREATE TABLE  FlurABXinpoutpat_V2 (compress=yes)  AS 
	SELECT A.*, B.got_abx_1day_dod_ind
	FROM  FlurABXinpoutpat_V1   A
	LEFT JOIN abx_1day_DOD  B ON A.patienticn =B.patienticn and  a.unique_hosp_count_id=b.unique_hosp_count_id  ;
QUIT;

PROC SQL;
	CREATE TABLE  FlurABXinpoutpat_V3 (compress=yes)  AS 
	SELECT A.*, B.sum_inpatabx_days_hosp, b.sum_outpatabx_days_hosp, b.sum_inoutpat_abx_days_hosp
	FROM  FlurABXinpoutpat_V2  A
	LEFT JOIN inoutpat_abx_days2  B ON A.patienticn =B.patienticn and  a.unique_hosp_count_id=b.unique_hosp_count_id  ;
QUIT;

/*Infection hospitalization indicator created*/
DATA temp.FlurABXinpoutpat_20190220_v2 (compress=yes); 
SET  FlurABXinpoutpat_V3;
if culture_hosp=1 AND (sum_inoutpat_abx_days_hosp >=3 OR got_abx_1day_dod_ind=1) then infection_hosp=1; else infection_hosp=0;
new_admityear=year(new_admitdate3);
RUN;

/*create indicators on the inpatient hospitalization level for a) any fluoroquinolone, b) ciprofloxacin, c) levofloxacin, d) moxifloxacin*/
DATA  abx_daily (compress=yes);
SET temp.FlurABXinpoutpat_20190220_v2 ;
if abx_med_1 in ('Levofloxacin_IV','Levofloxacin_PO') or  abx_med_2 in ('Levofloxacin_IV','Levofloxacin_PO') 
 or abx_med_3 in ('Levofloxacin_IV','Levofloxacin_PO') or  abx_med_4 in ('Levofloxacin_IV','Levofloxacin_PO') then Levofloxacin_daily=1;
   else  Levofloxacin_daily=0;
if abx_med_1 in ('Ciprofloxacin_PO','Ciprofloxacin_IV') or  abx_med_2 in ('Ciprofloxacin_PO','Ciprofloxacin_IV') 
 or abx_med_3 in ('Ciprofloxacin_PO','Ciprofloxacin_IV') or  abx_med_4 in ('Ciprofloxacin_PO','Ciprofloxacin_IV') then Ciprofloxacin_daily=1;
   else  Ciprofloxacin_daily=0;
if abx_med_1 in ('Moxifloxacin_PO','Moxifloxacin_IV') or  abx_med_2 in ('Moxifloxacin_PO','Moxifloxacin_IV') 
 or abx_med_3 in ('Moxifloxacin_PO','Moxifloxacin_IV') or  abx_med_4 in ('Moxifloxacin_PO','Moxifloxacin_IV') then Moxifloxacin_daily=1;
   else  Moxifloxacin_daily=0;
if Levofloxacin_daily=1 or Ciprofloxacin_daily=1 or  Moxifloxacin_daily=1
  then fluoroquinolone_daily=1; else fluoroquinolone_daily=0;
keep patienticn new_admitdate3 new_dischargedate3 unique_hosp_count_id Levofloxacin_daily Ciprofloxacin_daily Moxifloxacin_daily fluoroquinolone_daily;
RUN;

/*create hosp indicators and # of days*/
/*Levofloxacin*/
data levo_v1 (compress=yes); 
set abx_daily;
if Levofloxacin_daily=1;
Levofloxacin_hosp=1;
keep patienticn unique_hosp_count_id Levofloxacin_daily Levofloxacin_hosp ;
run;

/*Total number of days on any Levo*/
PROC SQL;
CREATE TABLE sum_levo_days_hosp   (compress=yes) AS  
SELECT *, sum(Levofloxacin_daily) as sum_levo_days_hosp 
FROM levo_v1
group by unique_hosp_count_id
order by patienticn, unique_hosp_count_id;
QUIT;

PROC SORT DATA=sum_levo_days_hosp nodupkey out=sum_levo_days_hosp2 (keep=Levofloxacin_hosp patienticn unique_hosp_count_id sum_levo_days_hosp); 
BY  patienticn unique_hosp_count_id sum_levo_days_hosp;
RUN; 

/*Ciprofloxacin*/
data cipro_v1 (compress=yes); 
set abx_daily;
if Ciprofloxacin_daily=1;
Ciprofloxacin_hosp=1;
keep patienticn unique_hosp_count_id Ciprofloxacin_daily Ciprofloxacin_hosp ;
run;

/*Total number of days on any Cipro*/
PROC SQL;
CREATE TABLE sum_cipro_days_hosp   (compress=yes) AS  
SELECT *, sum(Ciprofloxacin_daily) as sum_cipro_days_hosp 
FROM cipro_v1
group by unique_hosp_count_id
order by patienticn, unique_hosp_count_id;
QUIT;

PROC SORT DATA=sum_cipro_days_hosp nodupkey out=sum_cipro_days_hosp2 (keep=Ciprofloxacin_hosp patienticn unique_hosp_count_id sum_cipro_days_hosp); 
BY  patienticn unique_hosp_count_id sum_cipro_days_hosp;
RUN; 

/*Moxifloxacin*/
data moxi_v1 (compress=yes); 
set abx_daily;
if Moxifloxacin_daily=1;
Moxifloxacin_hosp=1;
keep patienticn unique_hosp_count_id Moxifloxacin_daily Moxifloxacin_hosp ;
run;

/*Total number of days on any Moxi*/
PROC SQL;
CREATE TABLE sum_moxi_days_hosp   (compress=yes) AS  
SELECT *, sum(Moxifloxacin_daily) as sum_moxi_days_hosp 
FROM moxi_v1
group by unique_hosp_count_id
order by patienticn, unique_hosp_count_id;
QUIT;

PROC SORT DATA=sum_moxi_days_hosp nodupkey out=sum_moxi_days_hosp2 (keep=Moxifloxacin_hosp patienticn unique_hosp_count_id sum_moxi_days_hosp); 
BY  patienticn unique_hosp_count_id sum_moxi_days_hosp;
RUN; 

/*Any fluoroquinolone*/
data fluoro_v1 (compress=yes); 
set abx_daily;
if fluoroquinolone_daily=1;
fluoroquinolone_hosp=1;
keep patienticn unique_hosp_count_id fluoroquinolone_daily fluoroquinolone_hosp ;
run;

/*Total number of days on any fluoroquinolone*/
PROC SQL;
CREATE TABLE sum_fluoro_days_hosp   (compress=yes) AS 
SELECT *, sum(fluoroquinolone_daily) as sum_fluoro_days_hosp 
FROM fluoro_v1
group by unique_hosp_count_id
order by patienticn, unique_hosp_count_id;
QUIT;

PROC SORT DATA=sum_fluoro_days_hosp nodupkey out=sum_fluoro_days_hosp2 (keep=fluoroquinolone_hosp patienticn unique_hosp_count_id sum_fluoro_days_hosp);
BY  patienticn unique_hosp_count_id sum_fluoro_days_hosp;
RUN;

/*daily level VAPD clean up*/
DATA VAPD_v1 (compress=yes);  
SET  temp.FlurABXinpoutpat_20190220_v2;
/*create quarter field based on admission date*/
quarter=qtr(new_admitdate3);
/*keep only certain fields*/
keep patienticn sta3n sta6a new_admitdate3 new_dischargedate3 quarter unique_hosp_count_id race female age elixhauser_vanwalraven
new_teaching  region hosp_LOS inhosp_mort mort30_admit readmit30_discharge cdc_hospcomm_sepsis VA_risk_scores new_admityear
unit_dx1-unit_dx26  angus_def_sepsis proccode_mechvent_daily proccode_dialysis_daily
PrescribingSta6a IssueDate LoginDate FillDateTime ReleaseDateTime MedicationRoute dis_day
releaseDate DispensedDate DaysSupply PharmacySiteName PharmacyOrderableItem
culture_hosp infection_hosp got_abx_1day_dod_ind sum_inpatabx_days_hosp sum_outpatabx_days_hosp sum_inoutpat_abx_days_hosp;
RUN;

/*left join abx indicators back to VAPD*/
PROC SQL;
	CREATE TABLE  FlurABXinpoutpat_20190220_v3 (compress=yes)  AS 
	SELECT A.*, B.fluoroquinolone_hosp, b.sum_fluoro_days_hosp,
	            c.Ciprofloxacin_hosp, c.sum_cipro_days_hosp,
			    d.Levofloxacin_hosp, d.sum_levo_days_hosp,
			    e.Moxifloxacin_hosp, e.sum_moxi_days_hosp
	FROM VAPD_v1   A
	LEFT JOIN sum_fluoro_days_hosp2  B ON A.patienticn =B.patienticn and a.unique_hosp_count_id=b.unique_hosp_count_id 
	LEFT JOIN sum_cipro_days_hosp2  C ON A.patienticn =c.patienticn and a.unique_hosp_count_id=c.unique_hosp_count_id 
	LEFT JOIN sum_levo_days_hosp2  D ON A.patienticn =d.patienticn and a.unique_hosp_count_id=d.unique_hosp_count_id 
	LEFT JOIN sum_moxi_days_hosp2  E ON A.patienticn =e.patienticn and a.unique_hosp_count_id=e.unique_hosp_count_id ;
QUIT;

DATA infection_hosp_only_daily (compress=yes) ; 
SET  FlurABXinpoutpat_20190220_v3;
if infection_hosp=1;
if culture_hosp =. then culture_hosp=0;
if got_abx_1day_dod_ind=. then got_abx_1day_dod_ind=0;
if fluoroquinolone_hosp=. then fluoroquinolone_hosp=0;
if sum_fluoro_days_hosp=. then sum_fluoro_days_hosp=0;
if Ciprofloxacin_hosp=. then Ciprofloxacin_hosp=0;
if sum_cipro_days_hosp=. then sum_cipro_days_hosp=0;
if Levofloxacin_hosp=. then Levofloxacin_hosp=0;
if sum_levo_days_hosp=. then sum_levo_days_hosp=0;
if Moxifloxacin_hosp=. then Moxifloxacin_hosp=0;
if sum_moxi_days_hosp=. then sum_moxi_days_hosp=0;
drop readmit30_discharge  cdc_hospcomm_sepsis inhosp_mort mort30_admit angus_def_sepsis proccode_mechvent_daily proccode_dialysis_daily
unit_dx1-unit_dx26 ;
RUN;

/*hosp level*/
PROC SORT DATA=infection_hosp_only_daily  nodupkey  OUT=temp.infection_hosp_only_20190221; 
BY  patienticn new_admitdate3 new_dischargedate3;
RUN;

/*add labels to variable names*/
data temp.infection_hosp_only_20190221 (compress=yes);
set temp.infection_hosp_only_20190221;
LABEL culture_hosp ='got culture done during hospitalization'
sum_inpatabx_days_hosp ='total # of inpatient days on any antibiotics during hospitalization'
sum_outpatabx_days_hosp='total # of outpatient days on any antibiotics during hospitalization'
sum_inoutpat_abx_days_hosp='total # of inpatient AND outpatient days on any antibiotics during hospitalization'
infection_hosp='definition: CULTURE + [ A) >3 days of ABX (inpat & outpat) OR B) Got ABX within 1 day of death]'
fluoroquinolone_hosp='got any fluoroquinolone during hospitalization indicator'
sum_fluoro_days_hosp='total # of inpatient days on any fluoroquinolone during hospitalization'
Ciprofloxacin_hosp='got any Ciprofloxacin during hospitalization indicator'
sum_cipro_days_hosp='total # of inpatient days on Ciprofloxacin during hospitalization'
Levofloxacin_hosp='got any Levofloxacin during hospitalization indicator'
sum_levo_days_hosp='total # of inpatient days on Levofloxacin during hospitalization'
Moxifloxacin_hosp='got any Moxifloxacin during hospitalization indicator'
sum_moxi_days_hosp='total # of inpatient days Moxifloxacin during hospitalization';
run;


/**********************************************************/
data Infection_hosp_only; 
set  temp.infection_hosp_only_20190221; 
run;

/*create outpatient med use indicators*/
data dis_meds_abx2; 
set dis_meds_abx2; 
patienticn_n=patienticn*1; 
run;

data dis_meds_abx3; 
set dis_meds_abx2;
/*admitday=input(new_admitdate2,mmddyy10.); format admitday mmddyy10.; 
year=year(admitday);*/
if drugnamewithoutdose in (/*'OFLOXACIN',*/'CIPROFLOXACIN','LEVOFLOXACIN','MOXIFLOXACIN' /*,'NORFLOXACIN'*/)
   then fluoro=1; 
    else if drugnamewithoutdose ne '' then fluoro=0; else fluoro=.;
if drugnamewithoutdose='CIPROFLOXACIN' then cipro=1; else if drugnamewithoutdose ne '' then cipro=0; else cipro=.;
if drugnamewithoutdose='LEVOFLOXACIN' then levo=1; else if drugnamewithoutdose ne '' then levo=0; else levo=.;
if drugnamewithoutdose='MOXIFLOXACIN' then moxi=1; else if drugnamewithoutdose ne '' then moxi=0; else moxi=.;
run;

*remove duplicate medications;
proc sort data=dis_meds_abx3 nodupkey; 
by patienticn_n dis_day drugnamewithoutdose; 
run;

*get results by patient discharge;
proc sql; 
create table outp_abx_pt as 
select patienticn_n as patienticn, dis_day, count(*) as abx_outpt_ct, sum(DaysSupply) as abx_outpt_days, sum(fluoro) as fluoro_outpt_ct, 
max(fluoro) as fluoro_outpt, sum(cipro) as cipro_outpt, sum(levo) as levo_outpt, sum(moxi) as moxi_outpt 
from dis_meds_abx3 
group by 1,2 
order by 1,2; 
quit;

proc sql; 
create table Fdays_abx_pt as 
select patienticn_n as patienticn, dis_day, sum(DaysSupply) as fluoro_days_outpt 
from dis_meds_abx3 
where fluoro=1 
group by 1,2 
order by 1,2; 
quit;

proc sql; 
create table Cdays_abx_pt as 
select patienticn_n as patienticn, dis_day, sum(DaysSupply) as cipro_days_outpt 
from dis_meds_abx3 
where cipro=1 
group by 1,2 
order by 1,2; 
quit;

proc sql; 
create table Ldays_abx_pt as 
select patienticn_n as patienticn, dis_day, sum(DaysSupply) as levo_days_outpt 
from dis_meds_abx3 
where levo=1 
group by 1,2 
order by 1,2; 
quit;

proc sql; 
create table Mdays_abx_pt as 
select patienticn_n as patienticn, dis_day, sum(DaysSupply) as moxi_days_outpt 
from dis_meds_abx3 
where moxi=1 
group by 1,2 
order by 1,2; 
quit;

proc sql; 
create table outp_abx_pt2 as 
select a.*, b.fluoro_days_outpt, c.cipro_days_outpt, d.levo_days_outpt, e.moxi_days_outpt 
from outp_abx_pt a 
left join Fdays_abx_pt b on a.patienticn=b.patienticn and a.dis_day=b.dis_day
left join Cdays_abx_pt c on a.patienticn=c.patienticn and a.dis_day=c.dis_day
left join Ldays_abx_pt d on a.patienticn=d.patienticn and a.dis_day=d.dis_day
left join Mdays_abx_pt e on a.patienticn=e.patienticn and a.dis_day=e.dis_day; 
quit;

proc sql; 
create table dis_meds_inf_abx as 
select a.*, b.abx_outpt_ct, b.abx_outpt_days, b.fluoro_outpt_ct, b.fluoro_outpt,
b.cipro_outpt, b.levo_outpt, b.moxi_outpt, b.fluoro_days_outpt, b.cipro_days_outpt, b.levo_days_outpt, b.moxi_days_outpt
from Infection_hosp_only a 
left join outp_abx_pt2 b on a.patienticn=b.patienticn and a.new_dischargedate3=b.dis_day; 
quit; 

data dis_meds_inf_abx; 
set dis_meds_inf_abx;
array zero (11) abx_outpt_ct abx_outpt_days fluoro_outpt_ct fluoro_outpt cipro_outpt levo_outpt moxi_outpt 
     fluoro_days_outpt cipro_days_outpt levo_days_outpt moxi_days_outpt;
do i=1 to 11; if zero(i)=. then zero(i)=0; end;
label abx_outpt_ct='# of outpatient ABX meds'
abx_outpt_days='# of outpatient ABX days'
fluoro_outpt_ct='# of outpatient FQ meds'
fluoro_outpt='indicator of outpatient FQ meds'
cipro_outpt='indicator of outpatient Cipro'
levo_outpt='indicator of outpatient Levo'
moxi_outpt='indicator of outpatient Moxi'
fluoro_days_outpt='# of outpatient FQ days'
cipro_days_outpt='# of outpatient Cipro days'
levo_days_outpt='# of outpatient Levo days'
moxi_days_outpt='# of outpatient Moxi days';
drop i;
run;

data temp.Inf_hosp_only_20190221_w_outpt; 
set dis_meds_inf_abx; 
run;


*** 3.18.19 - code for new tables;
proc means data=temp.Inf_hosp_only_20190221_w_outpt n nmiss mean std min max sum; 
class new_admityear; 
var fluoro_outpt cipro_outpt levo_outpt moxi_outpt fluoro_days_outpt cipro_days_outpt levo_days_outpt moxi_days_outpt; 
run;

data temp.Inf_hosp_only_20190221_w_outpt;
set temp.Inf_hosp_only_20190221_w_outpt; 
if fluoroquinolone_hosp=1 | fluoro_outpt=1 then fluoro=1; else fluoro=0;
fluoro_days=sum_fluoro_days_hosp+fluoro_days_outpt;
if Ciprofloxacin_hosp=1 | cipro_outpt=1 then cipro=1; else cipro=0;
cipro_days=sum_cipro_days_hosp+cipro_days_outpt;
if Levofloxacin_hosp=1 | levo_outpt=1 then levo=1; else levo=0;
levo_days=sum_levo_days_hosp+levo_days_outpt;
if Moxifloxacin_hosp=1 | moxi_outpt=1 then moxi=1; else moxi=0;
moxi_days=sum_moxi_days_hosp+moxi_days_outpt;
run;

proc means data=temp.Inf_hosp_only_20190221_w_outpt n nmiss mean std min max sum; class new_admityear; 
var fluoro cipro levo moxi fluoro_days cipro_days levo_days moxi_days; 
run;

/***********************************************************************************************************************************/
/*3/21/2019: update David's SAS table (inf_hosp_only_20190221_w_outpt) to include comorbid indicators*/
DATA  inf_hosp_only_20190221_w_outpt (compress=yes); 
SET  temp.inf_hosp_only_20190221_w_outpt;
RUN;

/*get back the comorbid indicators*/
PROC SQL;
CREATE TABLE FlurABXinpoutpat_20190220_v2   (COMPRESS=YES) AS 
SELECT A.* FROM temp.FlurABXinpoutpat_20190220_v2 AS A
WHERE A.unique_hosp_count_id IN (SELECT  unique_hosp_count_id  FROM inf_hosp_only_20190221_w_outpt);
QUIT;

PROC SORT DATA=FlurABXinpoutpat_20190220_v2  nodupkey out=temp.flu_comorbid_20190321 (compress=yes); 
BY unique_hosp_count_id elixhauser_vanwalraven ;
RUN;

PROC SQL;
	CREATE TABLE  temp.flu_inpoutpat_comorb20190321 (compress=yes)  AS 
	SELECT A.*, B.chf, b.cardic_arrhym , b.valvular_d2 , b.pulm_circ
    , b.pvd , b.htn_uncomp , b.htn_comp , b.paralysis , b.neuro , b.pulm , b.dm_uncomp , b.dm_comp , b.hypothyroid , b.renal , b.liver , b.pud
    , b.ah , b.lymphoma , b.cancer_met , b.cancer_nonmet , b.ra , b.coag , b.obesity , b.wtloss , b.fen , b.anemia_cbl , 
    b.anemia_def , b.etoh , b.drug , b.psychoses , b.depression
	FROM   inf_hosp_only_20190221_w_outpt  A
	LEFT JOIN FlurABXinpoutpat_20190220_v2   B
	ON A.unique_hosp_count_id =B.unique_hosp_count_id and a.elixhauser_vanwalraven=b.elixhauser_vanwalraven ;
QUIT;

/*****************************************************************************************************************************************/
/* 4/19/19: get # hospitalzations 2014-2017 for each facility using VAPD version temp.VAPD_VAtoVA20142017_20190219*/
PROC SORT DATA=temp.VAPD_VAtoVA20142017_20190219  nodupkey  OUT= unique_hosps (compress=yes); 
BY  unique_hosp_count_id;
RUN;

PROC SORT DATA=unique_hosps (compress=yes); 
BY   sta6a;
RUN;

/*give each ss hosp a count of 1 and then sum it up by sta6a*/
DATA unique_hosps2 (compress=yes); 
SET unique_hosps;
HospN=1;
RUN;

PROC SQL;
CREATE TABLE unique_hosps3  AS  
SELECT *, sum(HospN) as HospN_sta6a_20142017
FROM unique_hosps2
GROUP BY sta6a ;
QUIT;

PROC SORT DATA=unique_hosps3  nodupkey  OUT= unique_sta6a (compress=yes keep=sta6a HospN_sta6a_20142017);
BY  sta6a ;
RUN;

PROC SQL;
	CREATE TABLE flu_inpoutpat_comorb20190419  (compress=yes)  AS  
	SELECT A.*, B.HospN_sta6a_20142017
	FROM  temp.flu_inpoutpat_comorb20190321 A
	LEFT JOIN unique_sta6a   B ON A.sta6a =B.sta6a ;
QUIT;

/*further drop the some hosps with additional exlusion list */

/*age < 18*/
DATA version_1 (compress=yes) ; 
SET   flu_inpoutpat_comorb20190419;
if age <18 then delete;
RUN;

/*hosp with fewer than 400 hosps over 4 years*/
PROC SORT DATA=version_1  (compress=yes); 
BY   sta6a;
RUN;

/*give each ss hosp a count of 1 and then sum it up by sta6a*/
DATA version_1 (compress=yes); 
SET version_1;
HospN2=1;
RUN;

PROC SQL;
CREATE TABLE version_1b  AS  
SELECT *, sum(HospN2) as HospN2_sta6a_20142017
FROM version_1 
GROUP BY sta6a ;
QUIT;

DATA version_1c (compress=yes) ; 
SET  version_1b ;
if HospN2_sta6a_20142017<400 then delete;
drop HospN2  HospN2_sta6a_20142017;
RUN;

/*hospitals that enter or drop out of dataset over over years. Meaning a facility is missing in 2015  but showed up in 2016 and 2017, drop it*/
DATA  sta6a_check (compress=yes);
SET  version_1c;
admityear=year(new_admitdate3);
keep sta6a admityear;
RUN;

PROC SORT DATA=sta6a_check ; 
BY admityear sta6a ;
RUN;

PROC FREQ DATA=sta6a_check ;
where admityear=2014;
TABLE sta6a ;
RUN;

PROC FREQ DATA=sta6a_check ;
where admityear=2015;
TABLE sta6a ;
RUN;

PROC FREQ DATA=sta6a_check ;
where admityear=2016;
TABLE sta6a ;
RUN;

PROC FREQ DATA=sta6a_check ;
where admityear=2017;
TABLE sta6a ;
RUN;

/*stata=675 didn't show up consistently over the 4 years*/

DATA version_1d (compress=yes) ; /* 560,219 hosps, final infection hospitalizations cohort #*/
SET version_1c ;
if sta6a='675' then delete;
RUN;

/*save a sas and stata dataset*/
DATA temp.flu_inpoutpat_comorb20190419 (compress=yes); /* 560,219 hosps, final infection hospitalizations cohort #*/
SET  version_1d;
RUN;

/************ SANKEY BAR GRAPH ************/
/*use temp.flu_inpoutpat_comorb20190419 to create Sankey Bar Graph*/
*** Sankey Bar Chart ***;
proc sql; 
create table sankey_inp as select patienticn, new_dischargedate3, fluoroquinolone_hosp as fluoro, 
                     Ciprofloxacin_hosp as cipro, 
                     Levofloxacin_hosp as levo, 
					 moxifloxacin_hosp as moxi,
                     0 as time 
from temp.flu_inpoutpat_comorb20190419
order by 1; 
quit;


proc sql; 
create table sankey_dc as select patienticn, new_dischargedate3, fluoro_outpt as fluoro, 
                         cipro_outpt as cipro, levo_outpt as levo, moxi_outpt as  moxi,
       1 as time 
from temp.flu_inpoutpat_comorb20190419
order by 1; 
quit;

data sankey; 
set sankey_inp sankey_dc; 
if fluoro=. then fluoro=0; 
if cipro=. then cipro=0; 
if levo=. then levo=0; 
if moxi=. then moxi=0; 
if fluoro >1 then fluoro=1; 
length fluoro2 $3; 
if fluoro=1 then fluoro2='Yes'; 
 else fluoro2='No';
run;

proc sort data=sankey; 
by patienticn new_dischargedate3 time; 
run;

proc freq data=sankey; 
table fluoro fluoro2 time ; 
run;

*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*---------- THE FIRST INTERNAL MACRO ----------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;



/*--------------------------------------------------------------------------------------------------

SAS RawToSankey macro created by Shane Rosanbalm of Rho, Inc. 2015

*---------- high-level overview ----------;

-  The Sankey diagram macro requires data in two structures:
   -  The NODES dataset must be one record per bar segment.
   -  The LINKS dataset must be one record per connection between bar segments. 
-  This macro transforms a vertical dataset (i.e., one record per SUBJECT and XVAR) into the 
   Sankey NODES and LINKS structures.

*---------- required parameters ----------;

data=             vertical dataset to be converted to sankey structures

subject=          subject identifier

yvar=             categorical y-axis variable
                  converted to values 1-N for use in plotting
                  
xvar=             categorical x-axis variable
                  converted to values 1-N for use in plotting

*---------- optional parameters ----------;

outlib=           library in which to save NODES and LINKS datasets
                  default is the WORK library
                  
yvarord=          sort order for y-axis conversion, in a comma separated list
                     e.g., yvarord=%quote(red rum, george smith, tree)
                  default sort is equivalent to ORDER=DATA
                  
xvarord=          sort order for x-axis conversion, in a comma separated list
                     e.g., xvarord=%quote(pink plum, fred funk, grass)
                  default sort is equivalent to ORDER=DATA

-------------------------------------------------------------------------------------------------*/



%macro rawtosankey
   (data=
   ,subject=
   ,yvar=
   ,xvar=
   ,outlib=work
   ,yvarord=
   ,xvarord=
   );


   %*---------- localization ----------;
   
   %local i;
   
   
   %*---------- return code ----------;
   
   %global rts;
   %let rts = 0;
   

   %*-----------------------------------------------------------------------------------------;
   %*---------- display parameter values at the top (for debugging) ----------;
   %*-----------------------------------------------------------------------------------------;
   
   %put &=data;
   %put &=subject;
   %put &=yvar;
   %put &=xvar;
   %put &=outlib;
   %put &=yvarord;
   %put &=xvarord;
   
   
   
   %*-----------------------------------------------------------------------------------------;
   %*---------- basic parameter checks ----------;
   %*-----------------------------------------------------------------------------------------;
   
   
   %*---------- dataset exists ----------;
   
   %let _dataexist = %sysfunc(exist(&data));
   %if &_dataexist = 0 %then %do;
      %put RawToSankey -> DATASET [&data] DOES NOT EXIST;
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   
   %*---------- variables exist ----------;
   
   %macro varexist(data,var);
      %let dsid = %sysfunc(open(&data)); 
      %if &dsid %then %do; 
         %let varnum = %sysfunc(varnum(&dsid,&var));
         %if &varnum %then &varnum; 
         %else 0;
         %let rc = %sysfunc(close(&dsid));
      %end;
      %else 0;
   %mend varexist;
   
   %if %varexist(&data,&subject) = 0 %then %do;
      %put RawToSankey -> VARIABLE [&subject] DOES NOT EXIST;
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   %if %varexist(&data,&yvar) = 0 %then %do;
      %put RawToSankey -> VARIABLE [&yvar] DOES NOT EXIST;
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   %if %varexist(&data,&xvar) = 0 %then %do;
      %put RawToSankey -> VARIABLE [&xvar] DOES NOT EXIST;
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   

   %*---------- eject missing yvar records ----------;
   
   data _nodes00;
      set &data;
      where not missing(&yvar);
   run;
   
   
   %*---------- convert numeric yvar to character (for easier processing) ----------;
   
   %let dsid = %sysfunc(open(&data)); 
   %let varnum = %sysfunc(varnum(&dsid,&yvar));
   %let vartype = %sysfunc(vartype(&dsid,&varnum));
   %if &vartype = N %then %do; 
      data _nodes00;
         set _nodes00 (rename=(&yvar=_&yvar));
         &yvar = compress(put(_&yvar,best.));
         drop _&yvar;
      run;
   %end;
   %let rc = %sysfunc(close(&dsid));
   
   
   %*---------- convert numeric xvar to character (for easier processing) ----------;
   
   %let dsid = %sysfunc(open(&data)); 
   %let varnum = %sysfunc(varnum(&dsid,&xvar));
   %let vartype = %sysfunc(vartype(&dsid,&varnum));
   %if &vartype = N %then %do; 
      data _nodes00;
         set _nodes00 (rename=(&xvar=_&xvar));
         &xvar = compress(put(_&xvar,best.));
         drop _&xvar;
      run;
   %end;
   %let rc = %sysfunc(close(&dsid));
   
   
   %*---------- left justify xvar and yvar values (inelegant solution) ----------;
   
   data _nodes00;
      set _nodes00;
      &yvar = left(&yvar);
      &xvar = left(&xvar);
   run;
   
   
   %*---------- if no yvarord specified, build one using ORDER=DATA model ----------;
   
   proc sql noprint;
      select   distinct &yvar
      into     :yvar1-
      from     _nodes00
      ;
      %global n_yvar;
      %let n_yvar = &sqlobs;
      %put &=n_yvar;
   quit;
      
   %if &yvarord eq %str() %then %do;
   
      proc sql noprint;
         select   max(length(&yvar))
         into     :ml_yvar
         from     _nodes00
         ;
         %put &=ml_yvar;
      quit;
   
      data _null_;
         set _nodes00 (keep=&yvar) end=eof;
         array ordered {&n_yvar} $&ml_yvar;
         retain filled ordered1-ordered&n_yvar;
      
         *--- first record seeds array ---;
         if _N_ = 1 then do;
            filled = 1;
            ordered[filled] = &yvar;
         end;
      
         *--- if subsequent records not yet in array, add them ---;
         else do;
            hit = 0;
            do i = 1 to &n_yvar;
               if ordered[i] = &yvar then hit = 1;
            end;
            if hit = 0 then do;
               filled + 1;
               ordered[filled] = &yvar;
            end;
         end;
      
         *--- concatenate array elements into one variable ---;
         if eof then do;
            yvarord = catx(', ',of ordered1-ordered&n_yvar);
            call symputx('yvarord',yvarord);
         end;
      run;
      
   %end;

   %put &=yvarord;


   %*---------- if no xvarord specified, build one using ORDER=DATA model ----------;
   
   proc sql noprint;
      select   distinct &xvar
      into     :xvar1-
      from     _nodes00
      ;
      %global n_xvar;
      %let n_xvar = &sqlobs;
      %put &=n_xvar;
   quit;
      
   %if &xvarord eq %str() %then %do;
   
      proc sql noprint;
         select   max(length(&xvar))
         into     :ml_xvar
         from     _nodes00
         ;
         %put &=ml_xvar;
      quit;
   
      data _null_;
         set _nodes00 (keep=&xvar) end=eof;
         array ordered {&n_xvar} $&ml_xvar;
         retain filled ordered1-ordered&n_xvar;
      
         *--- first record seeds array ---;
         if _N_ = 1 then do;
            filled = 1;
            ordered[filled] = &xvar;
         end;
      
         *--- if subsequent records not yet in array, add them ---;
         else do;
            hit = 0;
            do i = 1 to &n_xvar;
               if ordered[i] = &xvar then hit = 1;
            end;
            if hit = 0 then do;
               filled + 1;
               ordered[filled] = &xvar;
            end;
         end;
      
         *--- concatenate array elements into one variable ---;
         if eof then do;
            xvarord = catx(', ',of ordered1-ordered&n_xvar);
            call symputx('xvarord',xvarord);
         end;
      run;
      
   %end;

   %put &=xvarord;


   %*---------- parse yvarord ----------;
   
   %let commas = %sysfunc(count(%bquote(&yvarord),%bquote(,)));
   %let n_yvarord = %eval(&commas + 1);
   %put &=commas &=n_yvarord;
   
   %do i = 1 %to &n_yvarord;
      %global yvarord&i;      
      %let yvarord&i = %scan(%bquote(&yvarord),&i,%bquote(,));
      %put yvarord&i = [&&yvarord&i];      
   %end;
   
   
   %*---------- parse xvarord ----------;
   
   %let commas = %sysfunc(count(%bquote(&xvarord),%bquote(,)));
   %let n_xvarord = %eval(&commas + 1);
   %put &=commas &=n_xvarord;
   
   %do i = 1 %to &n_xvarord;      
      %global xvarord&i;
      %let xvarord&i = %scan(%bquote(&xvarord),&i,%bquote(,));
      %put xvarord&i = [&&xvarord&i];      
   %end;
      
   
   %*-----------------------------------------------------------------------------------------;
   %*---------- yvarord vs. yvar ----------;
   %*-----------------------------------------------------------------------------------------;
   
   
   %*---------- same number of values ----------;

   %if &n_yvarord ne &n_yvar %then %do;
      %put RawToSankey -> NUMBER OF yvarord= VALUES [&n_yvarord];
      %put RawToSankey -> DOES NOT MATCH NUMBER OF yvar= VALUES [&n_yvar];
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   %*---------- put yvarord and yvar into quoted lists ----------;
   
   proc sql noprint;
      select   distinct quote(trim(left(&yvar)))
      into     :_yvarlist
      separated by ' '
      from     _nodes00
      ;
   quit;
   
   %put &=_yvarlist;
   
   data _null_;
      length _yvarordlist $2000;
      %do i = 1 %to &n_yvarord;
         _yvarordlist = trim(_yvarordlist) || ' ' || quote("&&yvarord&i");
      %end;
      call symputx('_yvarordlist',_yvarordlist);
   run;
   
   %put &=_yvarordlist;
   
   %*---------- check lists in both directions ----------;
   
   data _null_;
      array yvarord (&n_yvarord) $200 (&_yvarordlist);
      array yvar (&n_yvar) $200 (&_yvarlist);
      call symputx('_badyvar',0);
      %do i = 1 %to &n_yvarord;
         if "&&yvarord&i" not in (&_yvarlist) then call symputx('_badyvar',1);
      %end;
      %do i = 1 %to &n_yvar;
         if "&&yvar&i" not in (&_yvarordlist) then call symputx('_badyvar',2);
      %end;
   run;
   
   %if &_badyvar eq 1 %then %do;
      %put RawToSankey -> VALUE WAS FOUND IN yvarord= [&_yvarordlist];
      %put RawToSankey -> THAT IS NOT IN yvar= [&_yvarlist];
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   %if &_badyvar eq 2 %then %do;
      %put RawToSankey -> VALUE WAS FOUND IN yvar= [&_yvarlist];
      %put RawToSankey -> THAT IS NOT IN yvarord= [&_yvarordlist];
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
      

   %*-----------------------------------------------------------------------------------------;
   %*---------- xvarord vs. xvar ----------;
   %*-----------------------------------------------------------------------------------------;
   
   
   %*---------- same number of values ----------;
   
   %if &n_xvarord ne &n_xvar %then %do;
      %put RawToSankey -> NUMBER OF xvarord= VALUES [&n_xvarord];
      %put RawToSankey -> DOES NOT MATCH NUMBER OF xvar= VALUES [&n_xvar];
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   %*---------- put xvarord and xvar into quoted lists ----------;
   
   proc sql noprint;
      select   distinct quote(trim(left(&xvar)))
      into     :_xvarlist
      separated by ' '
      from     _nodes00
      ;
   quit;
   
   %put &=_xvarlist;
   
   data _null_;
      length _xvarordlist $2000;
      %do i = 1 %to &n_xvarord;
         _xvarordlist = trim(_xvarordlist) || ' ' || quote("&&xvarord&i");
      %end;
      call symputx('_xvarordlist',_xvarordlist);
   run;
   
   %put &=_xvarordlist;
   
   %*---------- check lists in both directions ----------;
   
   data _null_;
      array xvarord (&n_xvarord) $200 (&_xvarordlist);
      array xvar (&n_xvar) $200 (&_xvarlist);
      call symputx('_badxvar',0);
      %do i = 1 %to &n_xvarord;
         if "&&xvarord&i" not in (&_xvarlist) then call symputx('_badxvar',1);
      %end;
      %do i = 1 %to &n_xvar;
         if "&&xvar&i" not in (&_xvarordlist) then call symputx('_badxvar',2);
      %end;
   run;
   
   %if &_badxvar eq 1 %then %do;
      %put RawToSankey -> VALUE WAS FOUND IN xvarord= [&_xvarordlist];
      %put RawToSankey -> THAT IS NOT IN xvar= [&_xvarlist];
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   %if &_badxvar eq 2 %then %do;
      %put RawToSankey -> VALUE WAS FOUND IN xvar= [&_xvarlist];
      %put RawToSankey -> THAT IS NOT IN xvarord= [&_xvarordlist];
      %put RawToSankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
      

   %*-----------------------------------------------------------------------------------------;
   %*---------- enumeration ----------;
   %*-----------------------------------------------------------------------------------------;


   %*---------- enumerate yvar values ----------;
   
   proc sort data=_nodes00 out=_nodes05;
      by &yvar;
   run;
   
   data _nodes10;
      set _nodes05;
      by &yvar;
      %do i = 1 %to &n_yvarord;
         if &yvar = "&&yvarord&i" then y = &i;
      %end;
   run;
   
   
   %*---------- enumerate xvar values ----------;
   
   proc sort data=_nodes10 out=_nodes15;
      by &xvar;
   run;   
   
   data _nodes20;
      set _nodes15;
      by &xvar;
      %do i = 1 %to &n_xvarord;
         if &xvar = "&&xvarord&i" then x = &i;
      %end;
   run;
   
   
   %*---------- keep only complete cases ----------;
   
   proc sql noprint;
      select   max(x)
      into     :xmax
      from     _nodes20
      ;
      %put &=xmax;
   quit;
   
   proc sql;
      create table _nodes30 as
      select   *
      from     _nodes20
      group by &subject
      having   count(*) eq &xmax
      ;
   quit;

   
   %*-----------------------------------------------------------------------------------------;
   %*---------- transform raw data to nodes structure ----------;
   %*-----------------------------------------------------------------------------------------;


   proc sql;
      create table _nodes40 as
      select   x, y, count(*) as size
      from     _nodes30
      group by x, y
      ;
   quit;
   
   data &outlib..nodes;
      set _nodes40;
      length xc yc $200;
      %do i = 1 %to &n_xvarord;
         if x = &i then xc = "&&xvarord&i";
      %end;
      %do i = 1 %to &n_yvarord;
         if y = &i then yc = "&&yvarord&i";
      %end;
   run;

   
   %*-----------------------------------------------------------------------------------------;
   %*---------- transform raw data to links structure ----------;
   %*-----------------------------------------------------------------------------------------;


   proc sort data=_nodes30 out=_links00;
      by &subject x;
   run;
   
   data _links10;
      set _links00;
      by &subject x;
      retain lastx lasty;
      if first.&subject then call missing(lastx,lasty);
      else if lastx + 1 eq x then do;
         x1 = lastx;
         y1 = lasty;
         x2 = x;
         y2 = y;
         output;
      end;
      lastx = x;
      lasty = y;
   run;

   proc sql noprint;
      create table &outlib..links as
      select   x1, y1, x2, y2, count(*) as thickness
      from     _links10
      group by x1, y1, x2, y2
      ;
   quit;
   
   
   %*--------------------------------------------------------------------------------;
   %*---------- clean up ----------;
   %*--------------------------------------------------------------------------------;
   
   
   proc datasets library=work nolist;
      delete _nodes: _links:;
   run; quit;
   
   
   %*---------- return code ----------;
   
   %let rts = 1;
   


%mend rawtosankey;




*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*---------- THE SECOND INTERNAL MACRO ----------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;



/*--------------------------------------------------------------------------------------------------

SAS Sankey macro created by Shane Rosanbalm of Rho, Inc. 2015

*---------- high-level overview ----------;

-  This macro creates a stacked bar chart with sankey-like links between the stacked bars. 
   It is intended to display the change over time in subject endpoint values.
   These changes are depicted by bands flowing from left to right between the stacked bars. 
   The thickness of each band corresponds to the number of subjects moving from the left to 
   the right.
-  The macro assumes two input datasets exist: NODES and LINKS.
   -  Use the macro %RawToSankey to help build NODES and LINKS from a vertical dataset.
   -  The NODES dataset must be one record per bar segment, with variables:
      -  X and Y (the time and response), 
      -  XC and YC (the character versions of X and Y),
      -  SIZE (the number of subjects represented by the bar segment).
      -  The values of X and Y should be integers starting at 1.
      -  Again, %RawToSankey will build this dataset for you.
   -  The LINKS dataset must be one record per link, with variables:
      -  X1 and Y1 (the time and response to the left), 
      -  X2 and Y2 (the time and response to the right), 
      -  THICKNESS (the number of subjects represented by the band). 
      -  The values of X1, Y1, X2, and Y2 should be integers starting at 1.
      -  Again, %RawToSankey will build this dataset for you.
-  The chart is produced using SGPLOT. 
   -  The procedure contains one HIGHLOW statement per node (i.e., per bar segment).
   -  The procedure contains one BAND statement per link (i.e., per connecting band).
   -  The large volume of HIGHLOW and BAND statements is necessary to get color consistency in 
      v9.3 (in v9.4 we perhaps could have used attribute maps to clean things up a bit).
-  Any ODS GRAPHICS adjustments (e.g., HEIGHT=, WIDTH=, IMAGEFMT=, etc.) should be made prior to 
   calling the macro.
-  Any fine tuning of axes or other appearance options will need to be done in (a copy of) the 
   macro itself.

*---------- required parameters ----------;

There are no required parameters for this macro.

*---------- optional parameters ----------;

sankeylib=        Library where NODES and LINKS datasets live.
                  Default: WORK
                  
colorlist=        A space-separated list of colors: one color per response group.
                  Not compatible with color descriptions (e.g., very bright green).
                  Default: the qualitative Brewer palette.

barwidth=         Width of bars.
                  Values must be in the 0-1 range.
                  Default: 0.25.
                  
xfmt=             Format for x-axis/time.
                  Default: values of xvar variable in original dataset.

legendtitle=      Text to use for legend title.
                     e.g., legendtitle=%quote(Response Value)

interpol=         Method of interpolating between bars.
                  Valid values are: cosine, linear.
                  Default: cosine.

percents=         Show percents inside each bar.
                  Valid values: yes/no.
                  Default: yes.
                  
*---------- outstanding issues ----------;

-------------------------------------------------------------------------------------------------*/



%macro sankey
   (sankeylib=work
   ,colorlist=
   ,barwidth=0.25
   ,xfmt=
   ,legendtitle=
   ,interpol=cosine
   ,percents=yes
   );



   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;
   %*---------- some preliminaries ----------;
   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;



   %*---------- localization ----------;
   
   %local i j;
   
   
   %*---------- dataset exists ----------;
   
   %let _dataexist = %sysfunc(exist(&sankeylib..nodes));
   %if &_dataexist = 0 %then %do;
      %put Sankey -> DATASET [&sankeylib..nodes] DOES NOT EXIST;
      %put Sankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   data nodes;
      set &sankeylib..nodes;
   run;
   
   %let _dataexist = %sysfunc(exist(&sankeylib..links));
   %if &_dataexist = 0 %then %do;
      %put Sankey -> DATASET [&sankeylib..links] DOES NOT EXIST;
      %put Sankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   data links;
      set &sankeylib..links;
   run;
   
   %*---------- variables exist ----------;
   
   %macro varexist(data,var);
      %let dsid = %sysfunc(open(&data)); 
      %if &dsid %then %do; 
         %let varnum = %sysfunc(varnum(&dsid,&var));
         %if &varnum %then &varnum; 
         %else 0;
         %let rc = %sysfunc(close(&dsid));
      %end;
      %else 0;
   %mend varexist;
   
   %if %varexist(nodes,x) = 0 or %varexist(nodes,y) = 0 or %varexist(nodes,size) = 0 %then %do;
      %put Sankey -> DATASET [work.nodes] MUST HAVE VARIABLES [x y size];
      %put Sankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   %if %varexist(links,x1) = 0 or %varexist(links,y1) = 0 or %varexist(links,x2) = 0 
         or %varexist(links,y2) = 0 or %varexist(links,thickness) = 0 %then %do;
      %put Sankey -> DATASET [work.links] MUST HAVE VARIABLES [x1 y1 x2 y2 thickness];
      %put Sankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   
   %*---------- preliminary sorts (and implicit dataset/variable checking) ----------;
   
   proc sort data=nodes;
      by y x size;
   run;

   proc sort data=links;
      by x1 y1 x2 y2 thickness;
   run;
   
   %*---------- break apart colors ----------;

   %if &colorlist eq %str() 
      %then %let colorlist = cxa6cee3 cx1f78b4 cxb2df8a cx33a02c cxfb9a99 cxe31a1c 
                             cxfdbf6f cxff7f00 cxcab2d6 cx6a3d9a cxffff99 cxb15928;
   %let n_colors = %sysfunc(countw(&colorlist));
   %do i = 1 %to &n_colors;
      %let color&i = %scan(&colorlist,&i,%str( ));
      %put color&i = [&&color&i];
   %end;
   
   %*---------- xfmt ----------;
   
   %if &xfmt eq %str() %then %do;
   
      %let xfmt = xfmt.;
      
      proc format;
         value xfmt
         %do 
            i = 1 %to &n_xvar;
            &i = "&&xvarord&i"
         %end;
         ;
      run;
      
   %end;
   
   %put &=xfmt;
   
   %*---------- number of rows ----------;

   proc sql noprint;
      select   max(y)
      into     :maxy
      from     nodes
      ;
   quit;
   
   %*---------- number of time points ----------;

   proc sql noprint;
      select   max(x)
      into     :maxx
      from     nodes
      ;
   quit;
   
   %*---------- corresponding text ----------;
   
   proc sql noprint;
      select   distinct y, yc
      into     :dummy1-, :yvarord1-
      from     nodes
      ;
   quit;
   
   %do i = 1 %to &sqlobs;
      %put yvarord&i = [&&yvarord&i];
   %end;
   
   %*---------- validate interpol ----------;
   
   %let _badinterpol = 0;
   data _null_;
      if      upcase("&interpol") = 'LINEAR' then call symput('interpol','linear');
      else if upcase("&interpol") = 'COSINE' then call symput('interpol','cosine');
      else call symput('_badinterpol','1');
   run;
   
   %if &_badinterpol eq 1 %then %do;
      %put Sankey -> THE VALUE INTERPOL= [&interpol] IS INVALID.;
      %put Sankey -> THE MACRO WILL STOP EXECUTING.;
      %return;
   %end;
   


   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;
   %*---------- convert counts to percents for nodes ----------;
   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;
   
   
   
   ods select none;
   ods output crosstabfreqs=_ctfhl (where=(_type_='11'));
   proc freq data=nodes;
      table x*y;
      weight size;
   run;
   ods select all;
   
   data _highlow;
      set _ctfhl;
      by x;
      node = _N_;
      retain cumpct;
      if first.x then cumpct = 0;
      low = cumpct;
      high = cumpct + rowpercent;
      cumpct = high;   
      keep x y node low high;   
   run;
   
   proc sql noprint;
      select   max(node)
      into     :maxhighlow
      from     _highlow
      ;
   quit;



   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;
   %*---------- write a bunch of highlow statements ----------;
   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;



   data _highlow_statements;
      set _highlow;
      by x;
      length highlow $200 color $20 legendlabel $40 scatter $200;

      %*---------- choose color based on y ----------;
      %do c = 1 %to &maxy;
         if y = &c then color = "&&color&c";
      %end;

      %*---------- create node specific x, low, high variables and write highlow statement ----------;
      %do j = 1 %to &maxhighlow;
         %let jc = %sysfunc(putn(&j,z%length(&maxhighlow).));
         %let jro = %sysfunc(mod(&j,&maxy));
         %if &jro = 0 %then %let jro = &maxy;
         if node = &j then do;
            xb&jc = x;
            lowb&jc = low;
            highb&jc = high;
            legendlabel = "&&yvarord&jro";
            highlow = "highlow x=xb&jc low=lowb&jc high=highb&jc / type=bar barwidth=&barwidth" ||
               " fillattrs=(color=" || trim(color) || ")" ||
               " name='" || trim(color) || "' legendlabel='" || trim(legendlabel) || "';";
            *--- sneaking in a scatter statement for percent annotation purposes ---;
            mean = mean(low,high);
            percent = high - low;
            if percent >= 1 then do;
               meanb&jc = mean;
               textb&jc = compress(put(percent,3.)) || '%';
               scatter = "scatter x=xb&jc y=meanb&jc / x2axis markerchar=textb&jc;";
            end;
         end;
      %end;

   run;

   proc sql noprint;
      select   distinct trim(highlow)
      into     :highlow
      separated by ' '
      from     _highlow_statements
      where    highlow is not missing
      ;
   quit;

   %put highlow = [%nrbquote(&highlow)];

   proc sql noprint;
      select   distinct trim(scatter)
      into     :scatter
      separated by ' '
      from     _highlow_statements
      where    scatter is not missing
      ;
   quit;

   %put scatter = [%nrbquote(&scatter)];
   
   
   %*---------- calculate offset based on bar width and maxx ----------;
   
   data _null_;
      if &maxx = 2 then offset = 0.25;
      else if &maxx = 3 then offset = 0.15;
      else offset = 0.05 + 0.03*((&barwidth/0.25)-1);
      call symputx ('offset',offset);
   run;   



   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;
   %*---------- convert counts to percents for links ----------;
   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;



   %*---------- number of subjects overall ----------;
   
   proc sql noprint;
      select   sum(size)
      into     :denom trimmed
      from     nodes
      where    x = 1
      ;
   quit;
   
   %put NOTE- &=denom;
      
   %*---------- left edge of each band ----------;
   
   data _links2;
      set links;
      by x1 y1 x2 y2;
      link = _N_;
      retain lastybhigh1;
      if first.x1 then lastybhigh1 = 0;
      xt1 = x1;
      yblow1 = lastybhigh1;
      ybhigh1 = lastybhigh1 + thickness/&denom;
      lastybhigh1 = ybhigh1;
   run;
   
   proc sort data=_links2 out=_links3;
      by x2 y2 x1 y1;
   run;
   
   %*---------- right edge of each band ----------;
   
   data _links3;
      set _links3;
      by x2 y2 x1 y1;
      retain lastybhigh2;
      if first.x2 then lastybhigh2 = 0;
      xt2 = x2;
      yblow2 = lastybhigh2;
      ybhigh2 = lastybhigh2 + thickness/&denom;
      lastybhigh2 = ybhigh2;
   run;
   
   %*---------- make vertical ----------;
   
   data _links4;
      set _links3;
      
      xt1alt = xt1 + &barwidth*0.48;
      xt2alt = xt2 - &barwidth*0.48;
      
      %if &interpol eq linear %then %do;
      
         do xt = xt1alt to xt2alt by 0.01;
            *--- low ---;
            mlow = (yblow2 - yblow1) / (xt2alt - xt1alt);
            blow = yblow1 - mlow*xt1alt;
            yblow = mlow*xt + blow;
            *--- high ---;
            mhigh = (ybhigh2 - ybhigh1) / (xt2alt - xt1alt);
            bhigh = ybhigh1 - mhigh*xt1alt;
            ybhigh = mhigh*xt + bhigh;
            output;
         end;
         
      %end;

      %if &interpol eq cosine %then %do;
      
         do xt = xt1alt to xt2alt by 0.01;
            b = constant('pi')/(xt2alt-xt1alt);
            c = xt1alt;
            *--- low ---;
            alow = (yblow1 - yblow2) / 2;
            dlow = yblow1 - ( (yblow1 - yblow2) / 2 );
            yblow = alow * cos( b*(xt-c) ) + dlow;
            *--- high ---;
            ahigh = (ybhigh1 - ybhigh2) / 2;
            dhigh = ybhigh1 - ( (ybhigh1 - ybhigh2) / 2 );
            ybhigh = ahigh * cos( b*(xt-c) ) + dhigh;
            output;
         end;
         
      %end;
      
      keep xt yblow ybhigh link y1;
   run;
   
   proc sort data=_links4;
      by link xt;
   run;
   
   %*---------- number of links ----------;

   proc sql noprint;
      select   max(link)
      into     :maxband
      from     _links4
      ;
   quit;
   
   %*---------- write the statements ----------;
   
   data _band_statements;
      set _links4;
      by link xt;
      length band $200 color $20;

      %*---------- choose color based on y1 ----------;
      %do c = 1 %to &maxy;
         if y1 = &c then color = "&&color&c";
      %end;

      %*---------- create link specific x, y variables and write series statements ----------;
      %do j = 1 %to &maxband;
         %let jc = %sysfunc(putn(&j,z%length(&maxband).));
         if link = &j then do;
            xt&jc = xt;
            yblow&jc = 100*yblow;
            ybhigh&jc = 100*ybhigh;
            band = "band x=xt&jc lower=yblow&jc upper=ybhigh&jc / x2axis transparency=0.5" || 
               " fill fillattrs=(color=" || trim(color) || ")" ||
               " ;";
         end;
      %end;

   run;

   proc sql noprint;
      select   distinct trim(band)
      into     :band
      separated by ' '
      from     _band_statements
      where    band is not missing
      ;
   quit;

   %put band = [%nrbquote(&band)];
   
                     
   
   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;
   %*---------- plot it ----------;
   %*----------------------------------------------------------------------------------------------;
   %*----------------------------------------------------------------------------------------------;
   
   
   
   data _all;
      set _highlow_statements _band_statements;
   run;
   
   proc sgplot data=_all noautolegend;
      %*---------- plotting statements ----------;
      &band;
      &highlow;
      %if &percents = yes %then &scatter;;
      %*---------- axis and legend statements ----------;
      x2axis display=(nolabel noticks) min=1 max=&maxx integer offsetmin=&offset offsetmax=&offset 
         tickvalueformat=&xfmt labelattrs=( size=15pt )  valueattrs=( size=15pt);
      xaxis display=none type=discrete offsetmin=&offset offsetmax=&offset 
         tickvalueformat=&xfmt labelattrs=( size=15pt ) valueattrs=( size=15pt);
      yaxis offsetmin=0.02 offsetmax=0.02 label="Percent" labelattrs=( size=15pt) valueattrs=(size=12pt);
      keylegend %do i = 1 %to &maxy; "&&color&i" %end; / title="&legendtitle" TITLEATTRS=(Size=15) valueattrs=(size=15pt);
   run;
   

   %*--------------------------------------------------------------------------------;
   %*---------- clean up ----------;
   %*--------------------------------------------------------------------------------;
   
   
   proc datasets library=work nolist;
      delete _nodes: _links: _all: _band: _highlow: _ctfhl;
   run; quit;
   


%mend sankey;




*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*---------- THE CONTAINER MACRO ----------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;
*-----------------------------------------------------------------------------------------;



/*-------------------------------------------------------------------------------------------------

SAS SankeyBarChart macro created by Shane Rosanbalm of Rho, Inc. 2015

*---------- high-level overview ----------;

-  This macro creates a stacked bar chart with Sankey-like links between the stacked bars. 
   The graphic is intended to display the change over time in categorical subject endpoint 
   values. These changes are depicted by bands flowing from left to right between the stacked 
   bars. The thickness of each band corresponds to the number of subjects moving from the left 
   to the right.
-  This macro is actually just a wrapper macro that contains two smaller macros. 
   -  The first inner macro, %RawToSankey, performs a data transformation. Assuming an input  
      dataset that is vertical (i.e., one record per subject and visit), the macro 
      generates two sets of counts:
      (a)   The number of subjects at each endpoint*visit combination (aka, NODES).
            E.g., how many subjects had endpoint=1 at visit=3?
      (b)   The number of subjects transitioning between endpoint categories at adjacent 
            visits (aka LINKS).
            E.g., how many subjects had endpoint=1 at visit=3 and endpoint=3 at visit=4?
      -  By default the endpoint and visit values are sorted using the ORDER=DATA principle.
         The optional parameter yvarord= and xvarord= can be used to change the display order.
   -  The second inner macro, %Sankey, uses SGPLOT to generate the bar chart (using the NODES 
      dataset) and the Sankey-like connectors (using the LINKS dataset).
      -  Any ODS GRAPHICS adjustments (e.g., HEIGHT=, WIDTH=, IMAGEFMT=, etc.) should be made 
         prior to calling the macro.
      -  There are a few optional parameters for changing the appearance of the graph (colors, 
         bar width, x-axis format, etc.), but it is likely that most seasoned graphers will want 
         to further customize the resulting figure. In that case, it is probably best to simply 
         make a copy of the %Sankey macro and edit away.

*---------- required parameters ----------;

data=             vertical dataset to be converted to sankey structures

subject=          subject identifier

yvar=             categorical y-axis variable
                  converted to values 1-N for use in plotting
                  
xvar=             categorical x-axis variable
                  converted to values 1-N for use in plotting

*---------- optional parameters ----------;

yvarord=          sort order for y-axis conversion, in a comma separated list
                     e.g., yvarord=%quote(red rum, george smith, tree)
                  default sort is equivalent to ORDER=DATA
                  
xvarord=          sort order for x-axis conversion, in a comma separated list
                     e.g., xvarord=%quote(pink plum, fred funk, grass)
                  default sort is equivalent to ORDER=DATA

colorlist=        A space-separated list of colors: one color per yvar group.
                  Not compatible with color descriptions (e.g., very bright green).
                  Default: the qualititive Brewer palette.

barwidth=         Width of bars.
                  Values must be in the 0-1 range.
                  Default: 0.25.
                  
xfmt=             Format for x-axis/time.
                  Default: values of xvar variable in original dataset.

legendtitle=      Text to use for legend title.
                     e.g., legendtitle=%quote(Response Value)

interpol=         Method of interpolating between bars.
                  Valid values are: cosine, linear.
                  Default: cosine.

percents=         Show percents inside each bar.
                  Valid values: yes/no.
                  Default: yes.
                  
------------------------------------------------------------------------------------------------*/


%macro sankeybarchart
   (data=
   ,subject=
   ,yvar=
   ,xvar=
   ,yvarord=
   ,xvarord=
   ,colorlist=
   ,barwidth=0.25
   ,xfmt=
   ,legendtitle=15
   ,interpol=cosine
   ,percents=yes
   );
   

   %*---------- first inner macro ----------;

   *%include "rawtosankey.sas";
   
   %if &data eq %str() or &subject eq %str() or &yvar eq %str() or &xvar eq %str() %then %do;
      %put SankeyBarChart -> AT LEAST ONE REQUIRED PARAMETER IS MISSING;
      %put SankeyBarChart -> THE MACRO WILL STOP EXECUTING;
      %return;
   %end;

   %rawtosankey
      (data=&data
      ,subject=&subject
      ,yvar=&yvar
      ,xvar=&xvar
      %if &yvarord ne %then ,yvarord=&yvarord;
      %if &xvarord ne %then ,xvarord=&xvarord;
      );


   %*---------- second inner macro ----------;

   *%include "sankey.sas";

   %if &rts = 1 %then %do;
   
      %sankey
         (barwidth=&barwidth
         ,interpol=&interpol
         ,percents=&percents
         %if &colorlist ne %then ,colorlist=&colorlist;
         %if &xfmt ne %then ,xfmt=&xfmt;
         %if &legendtitle ne %then ,legendtitle=&legendtitle;
         );
      
   %end;

%mend sankeybarchart;
%sankeybarchart(data=sankey, subject=patienticn, yvar=fluoro2, xvar=time, 
      yvarord=%str(No,Yes), xvarord=%str(0,1), barwidth=0.6, xfmt=xfmt., legendtitle=%str(Prescribed Fluoroquinolone));

/**Additional table for demo based on meeting on 6/6/19*/
/*get single-level CCS and discharge disposition back */
DATA  VAtoVA_VAPD_copy (compress=yes); 
SET  temp.VAPD_VAtoVA20142017_20190219;
keep patienticn new_admitdate3 new_dischargedate3 singlelevel_ccs inhosp_mort unique_hosp_count_id hosp_LOS  icu;
RUN; 

PROC SORT DATA=VAtoVA_VAPD_copy  nodupkey  OUT=VAtoVA_VAPD_copy2 (compress=yes); 
BY  patienticn new_admitdate3 new_dischargedate3;
RUN;

PROC SQL;
	CREATE TABLE  Flu_inpoutpat_comorb20190611 (compress=yes)  AS /* 560219*/
	SELECT A.*, B.singlelevel_ccs, b.inhosp_mort
	FROM cohort.Flu_inpoutpat_comorb20190610    A
	LEFT JOIN VAtoVA_VAPD_copy2  B
	ON A.patienticn =B.patienticn and a.new_admitdate3=b.new_admitdate3 and a.new_dischargedate3=b.new_dischargedate3 ;
QUIT;

PROC FREQ DATA=Flu_inpoutpat_comorb20190611  order=freq;
TABLE  singlelevel_ccs inhosp_mort ;
RUN;

PROC FREQ DATA=Flu_inpoutpat_comorb20190611  order=freq;
TABLE  female race region new_teaching ;
RUN;

/*recode hypertension and diabetes*/
DATA  Flu_inpoutpat_comorb20190611_v2 (compress=yes);
SET Flu_inpoutpat_comorb20190611 ;
if dm_uncomp=1 or dm_comp=1 then diabetes=1; else diabetes=0;
if htn_uncomp=1 or htn_comp=1  then Htn=1; else htn=0;
RUN;

PROC FREQ DATA=Flu_inpoutpat_comorb20190611_v2  order=freq;
TABLE  chf cardic_arrhym pulm diabetes Htn renal liver cancer_met cancer_nonmet; 
run;

PROC MEANS DATA=Flu_inpoutpat_comorb20190611_v2  std MIN MAX MEAN MEDIAN Q1 Q3;
VAR  age va_risk_scores hosp_los;
RUN;

DATA Flu_inpoutpat_comorb20190611_v3 (compress=yes) ;
SET  Flu_inpoutpat_comorb20190611_v2;
if age >=65 then age_egt65=1; else age_egt65=0;
if age >=65 and htn=1 then age65_htn=1; else age65_htn=0; 
RUN;

PROC FREQ DATA=Flu_inpoutpat_comorb20190611_v3  order=freq;
TABLE age_egt65  age65_htn;
RUN;

/*get icu_hosp indicator*/
DATA icu (compress=yes); 
SET VAtoVA_VAPD_copy;
if icu=1;
keep patienticn new_admitdate3 new_dischargedate3 icu;
RUN;

PROC SORT DATA=icu   nodupkey  OUT=icu_hosp ;
BY  patienticn new_admitdate3 new_dischargedate3;
RUN;

PROC SQL;
	CREATE TABLE Flu_inpoutpat_comorb20190611_v4  (compress=yes)  AS
	SELECT A.*, B.icu as icu_hosp_ind
	FROM  Flu_inpoutpat_comorb20190611_v3   A
	LEFT JOIN icu_hosp  B
	ON A.patienticn =B.patienticn and a.new_admitdate3=b.new_admitdate3 and a.new_dischargedate3=b.new_dischargedate3;
QUIT;

PROC FREQ DATA=Flu_inpoutpat_comorb20190611_v4  order=freq;
TABLE  icu_hosp_ind;
RUN;

/*Duration of overall FQ use, Median (IQR), combine inpatient and outpatient, then look at them separately*/
DATA  FQ_days (compress=yes); /* 560219*/
SET  Flu_inpoutpat_comorb20190611_v4;
total_FQ_days=fluoro_days_outpt + sum_fluoro_days_hosp;
keep patienticn  new_admitdate3  new_dischargedate3 fluoro_days_outpt sum_fluoro_days_hosp total_FQ_days;
RUN;

PROC MEANS DATA=FQ_days   MEDIAN Q1 Q3;
VAR  fluoro_days_outpt sum_fluoro_days_hosp total_FQ_days;
RUN;

/*Duration of ever FQ use, Median (IQR), combine inpatient and outpatient, then look at them separately*/
DATA  ever_FQ_days (compress=yes); /* 209,602 hosp*/
SET  Flu_inpoutpat_comorb20190611_v4;
if fluoro_outpt=1 or fluoroquinolone_hosp=1;
total_FQ_days=fluoro_days_outpt + sum_fluoro_days_hosp;
keep patienticn  new_admitdate3  new_dischargedate3 fluoro_days_outpt sum_fluoro_days_hosp total_FQ_days fluoro_outpt fluoroquinolone_hosp;
RUN;

PROC MEANS DATA= ever_FQ_days  MEDIAN Q1 Q3;
VAR  fluoro_days_outpt sum_fluoro_days_hosp total_FQ_days;
RUN;

/*Duration of inpatient FQ use, Median (IQR), combine inpatient and outpatient, then look at them separately*/
DATA  inpt_FQ_days (compress=yes); /* 182,337 hosp*/
SET  Flu_inpoutpat_comorb20190611_v4;
if  fluoroquinolone_hosp=1;
total_FQ_days=fluoro_days_outpt + sum_fluoro_days_hosp;
keep patienticn  new_admitdate3  new_dischargedate3 fluoro_days_outpt sum_fluoro_days_hosp total_FQ_days fluoroquinolone_hosp;
RUN;

PROC MEANS DATA=inpt_FQ_days  MEDIAN Q1 Q3;
VAR  fluoro_days_outpt sum_fluoro_days_hosp total_FQ_days;
RUN;

/*Duration of outpatient FQ use, Median (IQR), combine inpatient and outpatient, then look at them separately*/
DATA  outpat_FQ_days (compress=yes); /* 110,003 hosp*/
SET  Flu_inpoutpat_comorb20190611_v4;
if fluoro_outpt=1 ;
total_FQ_days=fluoro_days_outpt + sum_fluoro_days_hosp;
keep patienticn  new_admitdate3  new_dischargedate3 fluoro_days_outpt sum_fluoro_days_hosp total_FQ_days fluoro_outpt ;
RUN;

PROC MEANS DATA=outpat_FQ_days  MEDIAN Q1 Q3;
VAR  fluoro_days_outpt sum_fluoro_days_hosp total_FQ_days;
RUN;

/*Getting ICU level and score, instead of only looking at hosp complexity*/
PROC IMPORT OUT = icu_level /*152*/
          FILE = "ICU LEVEL CSV FILE LOCATION"
          DBMS = CSV
          REPLACE;
RUN;

PROC SQL;
	CREATE TABLE Flu_inpoutpat_comorb20190611_v5 (compress=yes)  AS /* 560219 hosps*/
	SELECT A.*, B.icu_level, b.icu_score
	FROM   Flu_inpoutpat_comorb20190611_v4  A
	LEFT JOIN icu_level B
	ON a.sta6a=b.STA5A_parent_number;
QUIT;

DATA test ; /*0, no missings*/
SET  Flu_inpoutpat_comorb20190611_v5;
if icu_level = '' or icu_score=.;
RUN;

DATA Flu_inpoutpat_comorb20190611_v5 (compress=yes); /*560,219 hosps*/
SET Flu_inpoutpat_comorb20190611_v5;
drop sta3n_char  complexity_level;
if icu_hosp_ind NE 1 then icu_hosp_ind=0;
RUN;

PROC FREQ DATA=Flu_inpoutpat_comorb20190611_v5;
TABLE  icu_level icu_score;
RUN;


/*get admit and discharge date2 back */
PROC SORT DATA=temp.VAPD_VAtoVA20142017_20190219   nodupkey  OUT=VAPD_VAtoVA20142017_20190219 (keep=patienticn new_admitdate3 new_dischargedate3 new_admitdate2 new_dischargedate2);
BY patienticn new_admitdate3 new_dischargedate3 ;  
RUN;

PROC SQL;
	CREATE TABLE Flu_inpoutpat_comorb20190611_v6  (compress=yes)  AS /* 560219*/
	SELECT A.*, B.new_admitdate2, b.new_dischargedate2
	FROM  Flu_inpoutpat_comorb20190611_v5   A
	LEFT JOIN  VAPD_VAtoVA20142017_20190219  B
	ON A.patienticn =B.patienticn and a.new_admitdate3=b.new_admitdate3 and  a.new_dischargedate3=b.new_dischargedate3;
QUIT;


/*look at David's Discharge med dataset*/
PROC FREQ DATA=temp.Discharge_meds013119  order=freq;
TABLE  DrugNameWithoutDose;
RUN;

/*make a copy*/
DATA Discharge_meds013119 (compress=yes); 
SET cohort.Discharge_meds013119;
/*added: take out non_FQ drugs*/
if DrugNameWithoutDose in ('LEVOFLOXACIN', 'CIPROFLOXACIN', 'MOXIFLOXACIN'/*,'NORFLOXACIN'*/); 
RUN;

PROC FREQ DATA=Discharge_meds013119  order=freq;
TABLE  DrugNameWithoutDose MedicationRoute;
RUN;

/*get IV vs PO route info*/
DATA Discharge_meds013119 (compress=yes); 
SET Discharge_meds013119;
localdrugnamewithdose2=upcase(localdrugnamewithdose);  /*cap all localdrugnamewithdose*/
RUN;

/*indicate based on LocalDrugNameWithDose whether they are PO or IV*/
PROC SQL;
CREATE TABLE outpat_meds_v1   AS  
SELECT *, 
       case  when localdrugnamewithdose2  like '%TAB%' or  localdrugnamewithdose2  like '%ORAL%' or  localdrugnamewithdose2  like '% CAP%'
	   or  localdrugnamewithdose2  like  '%*CAP*%'  or  localdrugnamewithdose2  like '%SUSP%'
                    then 'PO'

	         when  localdrugnamewithdose2  like '% INJ%' or  localdrugnamewithdose2  like '% IV %' or  localdrugnamewithdose2  like '%VIAL%'
                    then 'IV'
			 ELSE 'PO'
			   END as route_recode
FROM Discharge_meds013119
GROUP BY route_recode
ORDER BY route_recode;
QUIT;

PROC SQL;
CREATE TABLE outpat_meds_v2   AS  
SELECT *, 
       case  when DrugNameWithoutDose  like '%LEVOFLOXACIN%' then 'LEVOFLOXACIN'
              when  DrugNameWithoutDose  like '%CIPROFLOXACIN%' then 'CIPROFLOXACIN'
	         when  DrugNameWithoutDose  like '%MOXIFLOXACIN%' then 'MOXIFLOXACIN'
/*           else 'OtherFQ'*/
			   END as outpat_med
FROM outpat_meds_v1;
QUIT;

PROC FREQ DATA=outpat_meds_v2  order=freq;
TABLE outpat_med ;
RUN;


/*combine outpat_med + route_recode*/
DATA  outpat_meds_v3 (compress=yes); 
SET outpat_meds_v2 ;
Underscore='_';
outpatmed_route=cats(outpat_med,Underscore,route_recode);
RUN;

/*are there multiple med_route by dis_day?*/
PROC SORT DATA= outpat_meds_v3 nodupkey out=checking (compress=yes keep=patienticn dis_day outpatmed_route); 
BY  patienticn dis_day outpatmed_route;
RUN;

/*need to transpose the dataset*/
PROC TRANSPOSE DATA=checking   OUT=outpat_meds_v4 (DROP=_NAME_ )  PREFIX= outpatmed_route_  ; 
BY patienticn dis_day;
VAR outpatmed_route;
RUN;

PROC FREQ DATA=outpat_meds_v4  order=freq;
TABLE  outpatmed_route_2;
RUN;


/*turn into outpat indicators*/
DATA  outpat_meds_v5 (compress=yes); /* 147664*/
SET outpat_meds_v4;
/* if outpatmed_route_1='OtherFQ_PO' or outpatmed_route_2='OtherFQ_PO'  
   then outpat_OtherFQ_PO=1; else outpat_OtherFQ_PO=0;
if outpatmed_route_1='OtherFQ_IV' or outpatmed_route_2='OtherFQ_IV' 
   then outpat_OtherFQ_IV=1; else outpat_OtherFQ_IV=0;*/

if outpatmed_route_1='LEVOFLOXACIN_PO' or outpatmed_route_2='LEVOFLOXACIN_PO' 
   then outpat_LEVO_PO=1; else outpat_LEVO_PO=0;
if outpatmed_route_1='LEVOFLOXACIN_IV' or outpatmed_route_2='LEVOFLOXACIN_IV'  
   then outpat_LEVO_IV=1; else outpat_LEVO_IV=0;

if outpatmed_route_1='CIPROFLOXACIN_PO' or outpatmed_route_2='CIPROFLOXACIN_PO'  
   then outpat_CIPRO_PO=1; else outpat_CIPRO_PO=0;
if outpatmed_route_1='CIPROFLOXACIN_IV' or outpatmed_route_2='CIPROFLOXACIN_IV'  
   then outpat_CIPRO_IV=1; else outpat_CIPRO_IV=0;

if outpatmed_route_1='MOXIFLOXACIN_PO' or outpatmed_route_2='MOXIFLOXACIN_PO'  
   then outpat_MOXI_PO=1; else outpat_MOXI_PO=0;
if outpatmed_route_1='MOXIFLOXACIN_IV' or outpatmed_route_2='MOXIFLOXACIN_IV'  
   then outpat_MOXI_IV=1; else outpat_MOXI_IV=0;

if outpat_MOXI_IV=1 or outpat_CIPRO_IV=1 or outpat_LEVO_IV=1 /*or outpat_OtherFQ_IV=1 */ then outpat_anyFQ_IV=1; else  outpat_anyFQ_IV=0;
if outpat_MOXI_PO=1 or outpat_CIPRO_PO=1 or outpat_LEVO_PO=1 /*or outpat_OtherFQ_PO=1 */ then outpat_anyFQ_PO=1; else  outpat_anyFQ_PO=0;
if outpat_anyFQ_IV=1 or outpat_anyFQ_PO=1 then outpat_anyFQ_IVPO=1; else outpat_anyFQ_IVPO=0;
RUN;

PROC FREQ DATA=outpat_meds_v5  order=freq;
TABLE outpat_anyFQ_IV outpat_anyFQ_PO  outpat_anyFQ_IVPO;
RUN;

/*change patienticn into numeric*/   
DATA outpat_meds_v5 (rename=patienticn2=patienticn);
SET outpat_meds_v5;
patienticn2 = input(patienticn, 10.);
drop patienticn;
RUN;

/*left join the outpat indicators back to infect. hosp dataset*/
PROC SQL;
	CREATE TABLE  Flu_inpoutpat_comorb20190611_v7 (compress=yes)  AS  /* 560,219*/
	SELECT A.*, b.outpat_LEVO_PO , b.outpat_LEVO_IV , b.outpat_CIPRO_PO , b.outpat_CIPRO_IV ,
	    b.outpat_MOXI_PO , b.outpat_MOXI_IV , b.outpat_anyFQ_IV , b.outpat_anyFQ_PO, b.outpat_anyFQ_IVPO
	FROM  Flu_inpoutpat_comorb20190611_v6   A
	LEFT JOIN  outpat_meds_v5 B
	ON A.patienticn =B.patienticn  and a.new_dischargedate3=b.dis_day;
QUIT;

/*inpatient drug data explore*/
DATA pharm_copy (compress=yes) ; 
SET  pharm.all_abx_07132018;
if  med_route not in (/*'Ofloxacin_PO', 'Ofloxacin_IV',*/ 'Ciprofloxacin_IV','Levofloxacin_IV', 'Ciprofloxacin_PO','Levofloxacin_PO', 
'Moxifloxacin_PO', 'Moxifloxacin_IV' /*, 'Norfloxacin_PO'*/) then delete;
run;

DATA pharm_copyA (compress=yes) ; /* 1263253*/
SET pharm_copy ;
if med_route='Levofloxacin_PO' then inpat_LEVO_PO=1; else inpat_LEVO_PO=0;
if med_route='Levofloxacin_IV' then inpat_LEVO_IV=1; else inpat_LEVO_IV=0;

if med_route='Ciprofloxacin_PO' then inpat_CIPRO_PO=1; else inpat_CIPRO_PO=0;
if med_route='Ciprofloxacin_IV' then inpat_CIPRO_IV=1; else inpat_CIPRO_IV=0;

if med_route='Moxifloxacin_PO' then inpat_MOXI_PO=1; else inpat_MOXI_PO=0;
if med_route='Moxifloxacin_IV' then inpat_MOXI_IV=1; else inpat_MOXI_IV=0;

if route2='IV' then inpat_anyFQ_IV=1; else inpat_anyFQ_IV=0;
if route2='PO' then inpat_anyFQ_PO=1; else inpat_anyFQ_PO=0;
if inpat_anyFQ_IV=1 or inpat_anyFQ_PO=1 then inpat_anyFQ_IVPO=1; else inpat_anyFQ_IVPO=0;
RUN;

DATA inpat_LEVO_PO (compress=yes keep=patienticn actiondate inpat_LEVO_PO)
     inpat_LEVO_IV (compress=yes keep=patienticn actiondate inpat_LEVO_IV)
	 inpat_CIPRO_PO (compress=yes keep=patienticn actiondate inpat_CIPRO_PO)
     inpat_CIPRO_IV (compress=yes keep=patienticn actiondate inpat_CIPRO_IV)
     inpat_MOXI_PO (compress=yes keep=patienticn actiondate inpat_MOXI_PO)
     inpat_MOXI_IV (compress=yes keep=patienticn actiondate inpat_MOXI_IV)
     inpat_anyFQ_PO (compress=yes keep=patienticn actiondate inpat_anyFQ_PO)
     inpat_anyFQ_IV (compress=yes keep=patienticn actiondate inpat_anyFQ_IV)
     inpat_anyFQ_IVPO (compress=yes keep=patienticn actiondate inpat_anyFQ_IVPO);
SET  pharm_copyA;
if inpat_LEVO_PO =1 then output inpat_LEVO_PO;
if  inpat_LEVO_IV =1 then output inpat_LEVO_IV;
if	inpat_CIPRO_PO =1 then output  inpat_CIPRO_PO;
if  inpat_CIPRO_IV =1 then output  inpat_CIPRO_IV;
if  inpat_MOXI_PO =1 then output  inpat_MOXI_PO;
if  inpat_MOXI_IV =1 then output  inpat_MOXI_IV;
if  inpat_anyFQ_PO =1 then output  inpat_anyFQ_PO;
if  inpat_anyFQ_IV =1 then output  inpat_anyFQ_IV;
if  inpat_anyFQ_IVPO =1 then output inpat_anyFQ_IVPO;
RUN;

PROC SORT DATA= inpat_LEVO_PO nodupkey;
BY patienticn actiondate inpat_LEVO_PO;
RUN;
PROC SORT DATA= inpat_LEVO_IV nodupkey;
BY patienticn actiondate inpat_LEVO_IV;
RUN;
PROC SORT DATA= inpat_CIPRO_PO nodupkey;
BY patienticn actiondate inpat_CIPRO_PO;
RUN;
PROC SORT DATA= inpat_CIPRO_IV nodupkey;
BY patienticn actiondate inpat_CIPRO_IV;
RUN;
PROC SORT DATA= inpat_MOXI_PO nodupkey;
BY patienticn actiondate inpat_MOXI_PO;
RUN;
PROC SORT DATA= inpat_MOXI_IV nodupkey;
BY patienticn actiondate inpat_MOXI_IV;
RUN;
PROC SORT DATA= inpat_anyFQ_PO nodupkey;
BY patienticn actiondate inpat_anyFQ_PO;
RUN;
PROC SORT DATA=inpat_anyFQ_IV nodupkey;
BY patienticn actiondate inpat_anyFQ_IV;
RUN;
PROC SORT DATA= inpat_anyFQ_IVPO nodupkey;
BY patienticn actiondate inpat_anyFQ_IVPO;
RUN;


/*match back to daily vapd*/
DATA VAPD_daily (compress=yes);  
SET  temp.FlurABXinpoutpat_20190220_v2;
/*keep only certain fields*/
keep patienticn datevalue sta3n sta6a new_admitdate3 new_dischargedate3  new_admitdate2 new_dischargedate3 unique_hosp_count_id;
run;

PROC SQL;
	CREATE TABLE  VAPD_daily2 (compress=yes)  AS
	SELECT A.*, B.inpat_LEVO_PO, c.inpat_LEVO_IV , d.inpat_CIPRO_PO , e.inpat_CIPRO_IV, f.inpat_MOXI_PO , g.inpat_MOXI_IV ,
	 h.inpat_anyFQ_IV , i.inpat_anyFQ_PO , j.inpat_anyFQ_IVPO
	FROM  VAPD_daily   A
	LEFT JOIN inpat_LEVO_PO B ON A.patienticn =B.patienticn and a.datevalue=b.actiondate 
    LEFT JOIN inpat_LEVO_IV c ON A.patienticn =c.patienticn and a.datevalue=c.actiondate 
	LEFT JOIN inpat_CIPRO_PO d ON A.patienticn =d.patienticn and a.datevalue=d.actiondate 
	LEFT JOIN inpat_CIPRO_IV e ON A.patienticn =e.patienticn and a.datevalue=e.actiondate 
	LEFT JOIN inpat_MOXI_PO f ON A.patienticn =f.patienticn and a.datevalue=f.actiondate 
	LEFT JOIN inpat_MOXI_IV g ON A.patienticn =g.patienticn and a.datevalue=g.actiondate 
	LEFT JOIN inpat_anyFQ_IV h ON A.patienticn =h.patienticn and a.datevalue=h.actiondate 
	LEFT JOIN inpat_anyFQ_PO i ON A.patienticn =i.patienticn and a.datevalue=i.actiondate 
	LEFT JOIN inpat_anyFQ_IVPO j ON A.patienticn =j.patienticn and a.datevalue=j.actiondate;
QUIT;

/*get vapd hosp level data*/
DATA inpat_LEVO_PO2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_LEVO_PO)
     inpat_LEVO_IV2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_LEVO_IV)
	 inpat_CIPRO_PO2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_CIPRO_PO)
     inpat_CIPRO_IV2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_CIPRO_IV)
     inpat_MOXI_PO2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_MOXI_PO)
     inpat_MOXI_IV2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_MOXI_IV)
     inpat_anyFQ_PO2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_anyFQ_PO)
     inpat_anyFQ_IV2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_anyFQ_IV)
     inpat_anyFQ_IVPO2 (compress=yes keep=patienticn new_admitdate3 new_dischargedate3 inpat_anyFQ_IVPO);
SET VAPD_daily2;
if inpat_LEVO_PO =1 then output inpat_LEVO_PO2;
if  inpat_LEVO_IV =1 then output inpat_LEVO_IV2;
if	inpat_CIPRO_PO =1 then output  inpat_CIPRO_PO2;
if  inpat_CIPRO_IV =1 then output  inpat_CIPRO_IV2;
if  inpat_MOXI_PO =1 then output  inpat_MOXI_PO2;
if  inpat_MOXI_IV =1 then output  inpat_MOXI_IV2;
if  inpat_anyFQ_PO =1 then output  inpat_anyFQ_PO2;
if  inpat_anyFQ_IV =1 then output  inpat_anyFQ_IV2;
if  inpat_anyFQ_IVPO =1 then output inpat_anyFQ_IVPO2;
RUN;

PROC SORT DATA= inpat_LEVO_PO2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_LEVO_PO;
RUN;
PROC SORT DATA= inpat_LEVO_IV2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_LEVO_IV;
RUN;
PROC SORT DATA= inpat_CIPRO_PO2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_CIPRO_PO;
RUN;
PROC SORT DATA= inpat_CIPRO_IV2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_CIPRO_IV;
RUN;
PROC SORT DATA= inpat_MOXI_PO2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_MOXI_PO;
RUN;
PROC SORT DATA= inpat_MOXI_IV2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_MOXI_IV;
RUN;
PROC SORT DATA= inpat_anyFQ_PO2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_anyFQ_PO;
RUN;
PROC SORT DATA=inpat_anyFQ_IV2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_anyFQ_IV;
RUN;
PROC SORT DATA= inpat_anyFQ_IVPO2 nodupkey;
BY patienticn new_admitdate3 new_dischargedate3 inpat_anyFQ_IVPO;
RUN;

PROC SQL;
	CREATE TABLE  Flu_inpoutpat_comorb20190611_v8 (compress=yes)  AS /* 560219*/
	SELECT A.*, B.inpat_LEVO_PO, c.inpat_LEVO_IV , d.inpat_CIPRO_PO , e.inpat_CIPRO_IV, f.inpat_MOXI_PO , g.inpat_MOXI_IV ,
	 h.inpat_anyFQ_IV , i.inpat_anyFQ_PO , j.inpat_anyFQ_IVPO
	FROM  Flu_inpoutpat_comorb20190611_v7  A
	LEFT JOIN inpat_LEVO_PO2 B ON A.patienticn =B.patienticn and a.new_admitdate3=b.new_admitdate3 and a.new_dischargedate3=b.new_dischargedate3
    LEFT JOIN inpat_LEVO_IV2 c ON A.patienticn =c.patienticn and a.new_admitdate3=c.new_admitdate3 and a.new_dischargedate3=c.new_dischargedate3
	LEFT JOIN inpat_CIPRO_PO2 d ON A.patienticn =d.patienticn and a.new_admitdate3=d.new_admitdate3 and a.new_dischargedate3=d.new_dischargedate3
	LEFT JOIN inpat_CIPRO_IV2 e ON A.patienticn =e.patienticn and a.new_admitdate3=e.new_admitdate3 and a.new_dischargedate3=e.new_dischargedate3 
	LEFT JOIN inpat_MOXI_PO2 f ON A.patienticn =f.patienticn and a.new_admitdate3=f.new_admitdate3 and a.new_dischargedate3=f.new_dischargedate3
	LEFT JOIN inpat_MOXI_IV2 g ON A.patienticn =g.patienticn and a.new_admitdate3=g.new_admitdate3 and a.new_dischargedate3=g.new_dischargedate3
	LEFT JOIN inpat_anyFQ_IV2 h ON A.patienticn =h.patienticn and a.new_admitdate3=h.new_admitdate3 and a.new_dischargedate3=h.new_dischargedate3
	LEFT JOIN inpat_anyFQ_PO2 i ON A.patienticn =i.patienticn and a.new_admitdate3=i.new_admitdate3 and a.new_dischargedate3=i.new_dischargedate3
	LEFT JOIN inpat_anyFQ_IVPO2 j ON A.patienticn =j.patienticn and a.new_admitdate3=j.new_admitdate3 and a.new_dischargedate3=j.new_dischargedate3;
QUIT;

/*get Weighted Elixhauser Comorbidity Index, Median (IQR) */
PROC MEANS DATA=Flu_inpoutpat_comorb20190611_v8   MIN MAX MEAN MEDIAN Q1 Q3;
VAR elixhauser_vanwalraven ;
RUN;


/*Received a Fluoroquinolone*/
/*inp or outpat*/
DATA anyFQ_v1 ; /*  209602*/
SET  Flu_inpoutpat_comorb20190611_v8;
if fluoroquinolone_hosp=1  or  fluoro_outpt=1;
RUN;

/*inpat only*/
DATA  inp_anyFQ_v1 (compress=yes); /* 182,337/560219=32.5%*/
SET  Flu_inpoutpat_comorb20190611_v8;
if /*inpat_anyFQ_IVPO=1 and*/ fluoroquinolone_hosp=1;
RUN;

PROC FREQ DATA= inp_anyFQ_v1 order=freq;
TABLE inpat_anyFQ_IV inpat_anyFQ_PO ;
RUN;

/*outpat only*/
DATA  out_anyFQ_v1 (compress=yes); /* 110003/560219=19.6*/
SET  Flu_inpoutpat_comorb20190611_v8;
if  fluoro_outpt=1; 
RUN;

PROC FREQ DATA= out_anyFQ_v1 order=freq;
TABLE outpat_anyFQ_IV outpat_anyFQ_PO ; /*14 missing IV/PO info*/
RUN;


/*Ciprofloxacin*/
/*inp and outpat*/
DATA anyCIPRO_v1 ; /*  90502/560219=16.2%*/
SET  Flu_inpoutpat_comorb20190611_v8;
if inpat_CIPRO_PO =1 or outpat_CIPRO_PO=1 or 
   inpat_CIPRO_IV =1 or outpat_CIPRO_IV=1;
RUN;

/*inpat only*/
DATA  inp_CIPRO_v1 (compress=yes); /*  76,450*/
SET  Flu_inpoutpat_comorb20190611_v8;
if inpat_CIPRO_PO =1  or inpat_CIPRO_IV =1;
RUN;

PROC FREQ DATA= inp_CIPRO_v1 order=freq;
TABLE inpat_CIPRO_PO inpat_CIPRO_IV ;
RUN;

/*outpat only*/
DATA  out_CIPRO_v1 (compress=yes); /* 45,189*/
SET  Flu_inpoutpat_comorb20190611_v8;
if outpat_CIPRO_PO =1  or outpat_CIPRO_IV =1;
RUN;

PROC FREQ DATA= out_CIPRO_v1 order=freq;
TABLE outpat_CIPRO_PO outpat_CIPRO_IV ;
RUN;

/*Levofloxacin*/
/*inp and outpat*/
DATA anyLEVO_v1 ; /*112,676/560219=20.1%*/
SET  Flu_inpoutpat_comorb20190611_v8;
if inpat_LEVO_PO =1 or outpat_LEVO_PO=1 or 
   inpat_LEVO_IV =1 or outpat_LEVO_IV=1;
RUN;

/*inpat only*/
DATA  inp_LEVO_v1 (compress=yes); /* 99,387*/
SET  Flu_inpoutpat_comorb20190611_v8;
if inpat_LEVO_PO =1  or inpat_LEVO_IV =1;
RUN;

PROC FREQ DATA= inp_LEVO_v1 order=freq;
TABLE inpat_LEVO_PO inpat_LEVO_IV ;
RUN;

/*outpat only*/
DATA  out_LEVO_v1 (compress=yes); /* 56,654*/
SET  Flu_inpoutpat_comorb20190611_v8;
if outpat_LEVO_PO =1  or outpat_LEVO_IV =1;
RUN;

PROC FREQ DATA= out_LEVO_v1 order=freq;
TABLE outpat_LEVO_PO outpat_LEVO_IV ;
RUN;

/*Moxifloxacin*/
/*inp and outpat*/
DATA anyMOXI_v1 ; /*16494/560219=2.9%*/
SET  Flu_inpoutpat_comorb20190611_v8;
if inpat_MOXI_PO =1 or outpat_MOXI_PO=1 or 
   inpat_MOXI_IV =1 or outpat_MOXI_IV=1;
RUN;

/*inpat only*/
DATA  inp_MOXI_v1 (compress=yes); /*14,176*/
SET  Flu_inpoutpat_comorb20190611_v8;
if inpat_MOXI_PO =1  or inpat_MOXI_IV =1;
RUN;

PROC FREQ DATA= inp_MOXI_v1 order=freq;
TABLE inpat_MOXI_PO inpat_MOXI_IV ;
RUN;

/*outpat only*/
DATA  out_MOXI_v1 (compress=yes); /*8,359*/
SET  Flu_inpoutpat_comorb20190611_v8;
if outpat_MOXI_PO =1  or outpat_MOXI_IV =1;
RUN;

PROC FREQ DATA= out_MOXI_v1 order=freq;
TABLE outpat_MOXI_PO outpat_MOXI_IV ;
RUN;
