# Master Key Access & Management: Multi-Scenario Analysis

**Discussion Document for Feature #1: Data Encryption at Rest**

**Date**: December 2025
**Purpose**: Define master key access policies for different trial scenarios
**Regulatory**: GDPR Article 28 + FDA 21 CFR Part 11

---

## SCENARIO 1: Pharmaceutical Trial (Multi-Site, Sponsor-Led)

### Trial Structure
```
SPONSOR: Pharma Company (CRO managing trial)
├─ Clinical Sites: 5 hospitals (Sites A-E)
├─ Principal Investigator: Physician at Site A
├─ Data Manager: CRO (Sponsor)
├─ Biostatistician: Contract lab (separate institution)
└─ FDA: Regulatory oversight
```

### Master Key Ownership & Access

**Master Key Holder: SPONSOR (Pharma/CRO)**
```
Who: Data Control Team at CRO
Location: AWS KMS (Sponsor's AWS account)
Access Control:
  - Sponsor DM: Full access (read/write key)
  - Sponsor QA: Read-only audit trail
  - Principal Investigator: No key access
  - Clinical Sites: No key access
  - Biostat Lab: No key access
```

### Database Architecture

```
┌─────────────────────────────────────────┐
│  SPONSOR (CRO)                          │
│  ┌──────────────────────────────────┐   │
│  │ Master Key (AWS KMS)             │   │
│  │ DB_ENCRYPTION_KEY_MASTER         │   │
│  └──────────────────────────────────┘   │
└─────────────┬───────────────────────────┘
              │
    ┌─────────┴──────────┬──────────────┬─────────────┐
    │                    │              │             │
    ▼                    ▼              ▼             ▼
┌─────────────┐  ┌──────────────┐  ┌──────────┐  ┌─────────────┐
│ Site A      │  │ Site B       │  │ Site C-E │  │ Biostat Lab │
│ Hospital 1  │  │ Hospital 2   │  │ Hospitals│  │ (Contract)  │
└─────────────┘  └──────────────┘  └──────────┘  └─────────────┘
      │                │                 │              │
      └─────────────────┴─────────────────┴──────────────┘
                       │
                ┌──────▼──────┐
                │  Database   │
                │  (encrypted)│
                │ w/ Master   │
                │  Key        │
                └─────────────┘
```

### Data Flow & Key Access

#### Phase 1: Data Entry (Clinical Sites)
```
Site A Coordinator enters vital signs
  │
  ├─ Query: INSERT INTO vitals (bp, hr, date)
  │
  ├─ Transmitted to: Sponsor's secure server (HTTPS)
  │
  ├─ Sponsor receives plaintext query
  │
  ├─ Sponsor encrypts with MASTER KEY (in memory)
  │
  ├─ Encrypted data stored in database
  │
  └─ Audit log: "Site A (User: John Doe) @ 14:32 INSERT subject_001"
```

**Site A Coordinator Access**:
- ❌ Cannot access master key
- ✅ Can submit data via Shiny interface
- ✅ Can view their own site's data (plaintext, decrypted server-side)
- ✅ Cannot see other sites' data

---

#### Phase 2: Data Monitoring (CRO)
```
CRO Data Manager wants to verify Site B data quality
  │
  ├─ Query: SELECT * FROM vitals WHERE site = 'B'
  │
  ├─ Query sent to database server
  │
  ├─ Database uses MASTER KEY to decrypt data
  │
  ├─ Plaintext results returned to CRO DM
  │
  └─ Audit log: "CRO (User: Jane Smith) @ 09:15 SELECT vitals"
```

**CRO Data Manager Access**:
- ✅ Has access to master key (through AWS KMS role)
- ✅ Can query all data across all sites
- ✅ Can view decrypted data
- ✅ Access logged with timestamp and purpose

---

#### Phase 3: Data Analysis (Biostat Lab)
```
Biostat Lab begins statistical analysis
  │
  ├─ Request: "Export clean dataset for ADAS-cog analysis"
  │
  ├─ CRO queries database with MASTER KEY
  │
  ├─ Decrypts required fields (ADAS-cog scores, dates, demographics)
  │
  ├─ Applies protocol-defined transformations
  │
  ├─ Exports CSV to secure location (encrypted transfer)
  │
  ├─ Biostat Lab receives CSV (no key included)
  │
  └─ Audit log: "CRO (User: Jane Smith) -> BiostatLab EXPORT analysis_dataset"
```

**Biostat Lab Access**:
- ❌ Does NOT receive master key
- ✅ Receives decrypted dataset export (CSV)
- ✅ Can perform analysis on exported data
- ❌ Cannot query encrypted database directly
- ✅ Requests additional data analysis through CRO

---

### Master Key Access Log (Audit Trail)

```
MASTER_KEY_ACCESS_LOG:

2025-06-01 08:30:15 | Action: KEY_DECRYPT | User: CRO_DM_JaneSmith | Purpose: Data_Entry_Processing | Status: SUCCESS
2025-06-01 09:15:42 | Action: KEY_DECRYPT | User: CRO_DM_JaneSmith | Purpose: Data_Quality_Review | Status: SUCCESS
2025-06-02 10:45:30 | Action: KEY_DECRYPT | User: CRO_QA_BobJones | Purpose: Audit_Trail_Verification | Status: SUCCESS
2025-06-15 14:32:15 | Action: KEY_DECRYPT | User: CRO_DM_JaneSmith | Purpose: Export_for_Biostat | Status: SUCCESS
2025-06-20 11:00:00 | Action: KEY_ROTATION | User: CRO_Admin | Purpose: Quarterly_Rotation | Status: SUCCESS | NewKeyId: arn:aws:kms:us-east-1:xxxxx

(No direct key access by: Sites A-E, Principal Investigator, or Biostat Lab)
```

### Transfer to Biostat Lab

```
PROCESS:

Step 1: CRO & Biostat Lab agreement
  ├─ Scope: Analysis dataset for ADAS-cog, CDR, weight change
  ├─ Timeline: 90 days
  └─ Confidentiality: Data remains under CRO control

Step 2: CRO prepares export
  ├─ CRO (with master key) queries database
  ├─ Decrypts required fields
  ├─ Applies protocol transformations
  ├─ Creates CSV: demographics, ADAS-cog, CDR, vitals
  └─ De-identifies if needed (PII removed)

Step 3: Secure transfer
  ├─ CSV encrypted with Biostat Lab's public key
  ├─ Transmitted via SFTP
  ├─ Biostat Lab decrypts with their private key
  └─ CRO retains master key (no transfer)

Step 4: Access revocation
  ├─ After 90 days, Biostat Lab access expires
  ├─ No need to change master key
  ├─ CRO audit trail shows: "Biostat_analysis_period_ended"
  └─ Data destroyed per protocol

Result: CRO ALWAYS HOLDS MASTER KEY
```

### Regulatory Compliance

**GDPR Article 28 (Data Processing Agreement)**:
```
✅ COMPLIANT:
- Sponsor is Data Controller (holds key, controls access)
- Sites & Biostat are Data Processors (no key access)
- Access control: Role-based, logged
- Sub-processors: Biostat Lab listed in DPA
```

**FDA 21 CFR Part 11 (Data Integrity)**:
```
✅ COMPLIANT:
- Sponsor maintains audit trail (key access logged)
- Electronic signatures: Sponsor controls
- Data accountability: Clear chain of custody
- Regulatory hold: Sponsor retains master key throughout
```

---

## SCENARIO 2: Academic Trial (5 Sites, University-Led)

### Trial Structure
```
PI: Professor at University Hospital (Site Lead)
├─ Participating Sites: 4 other university hospitals
├─ Data Coordinating Center: Same university as PI
├─ Biostatistician: Same university (internal)
└─ Funding: NIH grant (not pharma)
```

### Master Key Ownership & Access

**Master Key Holder: DATA COORDINATING CENTER (University)**
```
Who: Biostatistics/Research Computing team
Location: University's AWS account (or on-premises Vault)
Access Control:
  - Biostat Director: Full key access
  - DCC Manager: Full key access
  - PI (Professor): Audit-only access (cannot decrypt)
  - Site Coordinators: No key access
  - Other Sites' PIs: No key access
```

### Database Architecture

```
┌──────────────────────────────────────┐
│ UNIVERSITY DATA COORD CENTER         │
│ ┌──────────────────────────────────┐ │
│ │ Master Key (University Vault)    │ │
│ │ DB_ENCRYPTION_KEY_STUDY001       │ │
│ └──────────────────────────────────┘ │
└────────────────┬─────────────────────┘
                 │
        ┌────────┴────────────────┬─────────────┐
        │                         │             │
        ▼                         ▼             ▼
┌──────────────┐  ┌────────────────────┐  ┌──────────────┐
│ Site 1       │  │ Sites 2-5          │  │ University   │
│ (Univ Hosp)  │  │ (Partner Hospitals)│  │ Biostatistics│
└──────────────┘  └────────────────────┘  └──────────────┘
        │                 │                     │
        └─────────────────┴─────────────────────┘
                         │
                  ┌──────▼──────┐
                  │  Database   │
                  │  (encrypted)│
                  └─────────────┘
```

### Data Flow & Key Access

#### Phase 1: Data Entry (5 Sites)
```
Site 2 Coordinator enters lab results
  │
  └─ DCC decrypts with MASTER KEY → displays plaintext
     ├─ Site 2 can only see Site 2 data
     ├─ Other sites CANNOT see Site 2 data
     └─ Audit log: "Site2_Coord (User: Maria Garcia) @ 13:45 INSERT lab_results"
```

**Site Coordinators Access**:
- ❌ Cannot access master key
- ✅ Can enter data for their site
- ✅ Can view their own site's data (decrypted server-side)
- ❌ Cannot see other sites' data (privacy)

---

#### Phase 2: PI Oversight
```
PI (Professor) wants to check overall enrollment
  │
  ├─ Query: "Show enrollment by site"
  │
  ├─ DCC (with master key) decrypts and aggregates
  │
  ├─ Returns: Site 1: 25, Site 2: 28, Site 3: 22, Site 4: 26, Site 5: 23
  │
  └─ Audit log: "PI_Professor @ 10:30 SELECT enrollment_summary"
```

**PI Access**:
- ❌ Cannot access master key
- ✅ Can view aggregated/summary data
- ✅ Can request custom reports from DCC
- ❌ Cannot see individual subject data (DCC controls access)

---

#### Phase 3: Biostat Analysis (Internal University)
```
Biostatistician begins analysis
  │
  ├─ Direct access: Same institution, same master key
  │
  ├─ Can query full database with master key
  │
  ├─ Can access all sites' data (legitimate for statistical analysis)
  │
  └─ Audit log: "Biostat_Director @ 09:00 SELECT * FROM all_sites"
```

**Biostat Director Access**:
- ✅ HAS access to master key (same institution)
- ✅ Can query all sites' data
- ✅ Can perform comprehensive analysis
- ✅ All access logged to audit trail

---

### Master Key Governance

```
KEY MANAGEMENT COMMITTEE:
├─ Biostat Director (holds key)
├─ DCC Manager (alternate holder)
├─ PI (oversees governance, no technical access)
└─ Institutional Security Officer (compliance)

PROCEDURES:
- Key stored in University Vault (encrypted)
- Access requires multi-factor authentication (MFA)
- Monthly key access audit reviewed by committee
- Annual key rotation (new key generated)
- Key holder training: Annual HIPAA/GDPR training
```

### Transfer Scenario: External Biostat Lab

```
If external biostat lab needed:

Step 1: University DCC prepares export
  ├─ Queries database with master key
  ├─ Decrypts data
  ├─ Creates analysis dataset
  └─ De-identifies (remove names, MRNs)

Step 2: Secure transfer
  ├─ Encrypt CSV with external lab's key
  ├─ SFTP to external lab
  └─ University retains master key

Step 3: External lab analysis
  ├─ External lab decrypts with their key
  ├─ Performs analysis
  └─ Returns results to University

Result: Master key NEVER leaves University
        External lab has only exported data
```

### Regulatory Compliance

**GDPR (if EU data)**:
```
✅ COMPLIANT:
- University is Data Controller (holds key)
- Sites are Data Processors
- Biostat is internal (can access with key)
- External lab would need Data Processing Agreement
```

**NIH Requirements**:
```
✅ COMPLIANT:
- Audit trail requirement: Maintained
- Data retention: Controlled by University
- Access controls: Role-based by site
- Publication: University controls data access
```

---

## SCENARIO 3: Single-Site Trial with External Biostat Lab

### Trial Structure
```
Clinical Site: One hospital/clinic
├─ PI: Hospital physician (clinical director)
├─ Site Coordinator: Hospital staff
├─ Data Manager: Hospital research coordinator
├─ Biostatistician: EXTERNAL contract lab (separate institution)
└─ Funding: Foundation grant (not pharma)
```

### Master Key Ownership - Two Options

#### **OPTION A: Clinical Site Holds Master Key** (Full Control)

```
┌────────────────────────────────┐
│ CLINICAL SITE (Hospital)       │
│ ┌──────────────────────────────┐
│ │ Master Key (AWS KMS Account) │
│ │ DB_ENCRYPTION_KEY_TRIAL      │
│ └──────────────────────────────┘
└────────┬───────────────────────┘
         │
    ┌────┴─────┐
    │           │
    ▼           ▼
 Site DB    Biostat Lab
             (no key)
```

**Key Holder: CLINICAL SITE**
```
Who: Site PI or designated Data Manager
Location: Site's AWS KMS or Vault
Access: Only site personnel
```

**Biostat Lab Access**:
- ❌ Does NOT have master key
- ✅ Receives exported CSV (site decrypts, exports)
- ✅ Performs analysis on exported data
- ✅ Requests additional exports as needed

**Advantage**:
- ✅ Site retains full data control
- ✅ Biostat lab never sees encrypted database
- ✅ Clear separation of responsibilities
- ✅ Easy to revoke biostat access (just stop exporting)

**Disadvantage**:
- ⚠️ Site responsible for secure data export
- ⚠️ If site loses key, cannot access own data

---

#### **OPTION B: Biostat Lab Holds Master Key** (Analysis Control)

```
┌────────────────────────────────┐
│ BIOSTAT LAB (Contract)         │
│ ┌──────────────────────────────┐
│ │ Master Key (Lab's AWS Account)
│ │ DB_ENCRYPTION_KEY_TRIAL      │
│ └──────────────────────────────┘
└────────┬───────────────────────┘
         │
    ┌────┴─────┐
    │           │
    ▼           ▼
 Site DB    (encrypted by lab)
```

**Key Holder: BIOSTAT LAB**
```
Who: Lab director or designated analyst
Location: Lab's AWS KMS or Vault
Access: Lab personnel only
```

**Clinical Site Access**:
- ❌ Does NOT have master key
- ✅ Can submit data to lab
- ✅ Can view results
- ❌ Cannot directly decrypt database (depends on lab)

**Advantage**:
- ✅ Lab controls analysis environment
- ✅ Consistent security across projects
- ✅ Lab handles backups, maintenance

**Disadvantage**:
- ⚠️ Site cannot access own data without lab
- ⚠️ If lab loses key, site's data inaccessible
- ⚠️ GDPR issue: Lab = Data Processor, Site = Data Controller
  → Lab shouldn't hold encryption key (controller should)

---

#### **OPTION C: Dual Keys** (Recommended)

```
┌────────────────────────────────┐
│ CLINICAL SITE (Hospital)       │
│ ┌──────────────────────────────┐
│ │ Site Key (READ/WRITE)        │
│ │ DB_ENCRYPTION_KEY_SITE       │
│ └──────────────────────────────┘
└────────┬───────────────────────┘
         │
         ▼
      Database (encrypted with Site Key)
         │
         ├─ Site can encrypt/decrypt own data
         │
         └─ Biostat Lab needs Site Key to read
            (stored in escrow with Biostat Lab)

┌────────────────────────────────┐
│ BIOSTAT LAB (Contract)         │
│ ┌──────────────────────────────┐
│ │ Analysis Key (READ-ONLY)     │
│ │ DB_ENCRYPTION_KEY_ANALYSIS   │
│ │ (Can decrypt but not modify) │
│ └──────────────────────────────┘
└────────────────────────────────┘
```

**Key Management**:
- Site Key: Held by Site (read/write)
- Analysis Key: Shared with Lab (read-only for queries)
- Audit Trail: Lab queries logged, Site can verify

**Advantage**:
- ✅ Site maintains control (holds primary key)
- ✅ Lab has secure read-only access
- ✅ Clear separation: Site data owner, Lab analyst
- ✅ GDPR compliant (data controller holds primary key)
- ✅ Lab can access without receiving unencrypted data

**Disadvantage**:
- ⚠️ More complex implementation (feature #1 Phase 2)

---

### Master Key Transfer & Lifecycle

**Month 1-12: Data Collection & Entry**
```
Site holds master key
├─ PI enters data
├─ Coordinator reviews data quality
├─ Site monitors for missing fields
└─ Biostat Lab: Receives periodic exports
```

**Month 13: Database Transfer to Biostat Lab**
```
Option 1: Export & Transfer
  Site (with key) exports all data
    ├─ Decrypts with Site Key
    ├─ Creates CSV for analysis
    ├─ Transfers to Biostat Lab
    └─ Site retains master key

Option 2: Key Handoff (NOT recommended for GDPR)
  Site transfers master key to Lab
    ├─ Lab now can decrypt database
    ├─ Site loses independent access
    ├─ Risk: Lab could modify data
    └─ GDPR violation: Controller lost control

RECOMMENDATION: Use Option 1 (Export)
  - Site never transfers key
  - Lab gets data, not encryption capability
  - Maintains audit trail control
```

### Master Key Access Control

```
CLINICAL SITE:
- PI: Full key access (decrypt, manage)
- Data Manager: Full key access
- Coordinator: No key access (data entry only)
- Hospital IT: Can back up encrypted database
              (but not key)

BIOSTAT LAB:
- Lab Director: Limited access (read-only queries)
              (if using dual-key model)
- Analyst: No direct key access
```

### Audit Trail Example

```
SCENARIO: Site PI wants to prove data integrity to Biostat Lab

Audit Log:
2025-01-15 10:30:00 | PI_Physician @ Site | ACTION: Create_Subject_001
2025-01-15 14:45:00 | Coordinator @ Site | ACTION: Enter_Demographics
2025-01-16 09:15:00 | PI_Physician @ Site | ACTION: Enter_Baseline_Labs
2025-02-01 11:20:00 | Coordinator @ Site | ACTION: Enter_Visit_1_Forms
2025-02-15 13:30:00 | DataMgr @ Site | ACTION: Export_for_BiostatLab
2025-02-15 13:31:00 | PI_Physician @ Site | ACTION: KEY_ACCESS_DECRYPT_FOR_EXPORT
2025-02-15 14:00:00 | SYSTEM | ACTION: CSV_GENERATED (Subject_001: demographics, labs, forms)
2025-02-15 14:05:00 | SYSTEM | ACTION: CSV_TRANSMITTED_TO_BIOSTAT

Result: Clear audit trail showing:
  ✅ Site entered data
  ✅ When data was entered (timestamps)
  ✅ Who entered data (user IDs)
  ✅ Key access only for authorized export
  ✅ No unauthorized key access
  ✅ Biostat Lab received only exported CSV (not encrypted DB)
```

---

## REGULATORY COMPARISON TABLE

| Aspect | Pharma Trial | Academic (5 Sites) | Single-Site + Lab |
|--------|------------|------------------|---|
| **Master Key Holder** | Sponsor/CRO | University DCC | Site (Option A,C) or Lab (Option B) |
| **Key Access** | CRO staff only | Biostat team | Site staff (or Lab) |
| **Audit Trail** | Centralized at Sponsor | Decentralized (site + DCC) | Site-managed |
| **Site Access** | Via Sponsor API | Direct query (site data only) | Direct query |
| **Biostat Access** | Exported data only | Full access (internal) | Exported data (Option A/C) |
| **Data Control** | Sponsor/CRO | University | Site (Option A/C) |
| **GDPR Compliance** | ✅ Controller = Sponsor | ✅ Controller = University | ✅ Controller = Site |
| **FDA Compliance** | ✅ Audit trail maintained | ⚠️ Multi-institutional | ✅ Simple chain of custody |

---

## RECOMMENDATIONS FOR FEATURE #1 IMPLEMENTATION

### Phase 1 (Current): Single Master Key
```
✅ Implement for: Local development, single-institution trials
├─ Auto-generate master key
├─ Store in environment variable (.Renviron)
├─ Support export functionality
└─ Works for: Pharma (Sponsor), Academic, Single-Site scenarios
```

### Phase 2 (Future): Multi-Key Architecture
```
⏳ Implement for: Multi-site institutional control
├─ Master key (Sponsor/DCC/Site)
├─ Per-site encryption keys
├─ Read-only analysis keys
├─ Support key hierarchy
└─ Works for: Complex governance requirements
```

### Phase 3 (Future): Key Rotation & Escrow
```
⏳ Implement for: High-security trials
├─ Key rotation policies
├─ Key escrow (third-party holds backup)
├─ Key recovery procedures
├─ Compliance with FIPS 140-2
└─ Works for: Multi-institutional governance
```

---

## FEATURE #1 SCOPE DECISION

**For initial implementation (Feature #1)**:

✅ **INCLUDE**:
- Auto-generate single master key
- Store in environment variable
- Support export functionality for external labs
- Audit logging of key access
- AWS KMS integration path (for production)

❌ **DEFER TO PHASE 2+**:
- Per-site encryption keys
- Multi-key hierarchy
- Key rotation policies
- Key escrow procedures

---

## IMPLEMENTATION NOTES FOR Feature #1

### Code Design (Forward-Compatible)

```r
# Feature #1: Simple model
get_db_connection <- function() {
  key <- Sys.getenv("DB_ENCRYPTION_KEY")
  dbConnect(SQLite(), "data/study.db", key = key)
}

# Future: Phase 2 extension
get_db_connection <- function(user_id = NULL, key_type = "master") {
  if (key_type == "master") {
    key <- get_master_key()  # From AWS KMS
  } else if (key_type == "site") {
    key <- get_site_key(user_id)  # Per-site key
  } else if (key_type == "analysis") {
    key <- get_analysis_key(user_id)  # Read-only
  }
  dbConnect(SQLite(), "data/study.db", key = key)
}
```

### Documentation Requirements

```
Feature #1 Documentation must include:

1. Master Key Access Policy
   ├─ Who can access the key?
   ├─ How is access logged?
   ├─ What if key is compromised?
   └─ How to rotate key

2. Multi-Scenario Guidance
   ├─ Pharma trial setup
   ├─ Academic trial setup
   ├─ Single-site + external lab
   └─ When to use Option A vs B vs C (dual keys)

3. Data Export Process
   ├─ How to securely export for external labs
   ├─ What to include/exclude
   ├─ Audit trail of export
   └─ Recipient responsibilities

4. Regulatory Compliance
   ├─ GDPR Article 28 (Data Processing)
   ├─ FDA 21 CFR Part 11 (Audit Trail)
   ├─ IRB/Ethics requirements
   └─ Institutional policies
```

---

## CRISIS MANAGEMENT SCENARIO: Switching Biostat Labs Mid-Trial

### Realistic Trigger Events
```
Scenario A: Planned Transition (Low Risk)
  ├─ Contract ended, not renewed
  ├─ Timeline: 30+ days notice
  ├─ Reason: Cost savings, better capability
  └─ Complexity: Low (planned handoff)

Scenario B: Urgent Transition (Medium Risk)
  ├─ PI unhappy with turnaround time
  ├─ Timeline: 7-14 days notice
  ├─ Reason: Lab falling behind, slow responses
  └─ Complexity: Medium (rushed handoff)

Scenario C: Emergency Transition (High Risk)
  ├─ Lab goes out of business
  ├─ Timeline: Immediate (1-3 days)
  ├─ Reason: Lab closure, bankruptcy
  └─ Complexity: High (emergency procedures)

Scenario D: Security Incident (Critical Risk)
  ├─ Data breach suspected
  ├─ Timeline: Immediate
  ├─ Reason: Lab staff mishandles data, encryption concerns
  └─ Complexity: Critical (legal, regulatory notifications)

Scenario E: Contractual Dispute (Medium Risk)
  ├─ Lab and PI disagree on analysis approach
  ├─ Timeline: 10-20 days
  ├─ Reason: Statistical methodology disagreement
  └─ Complexity: Medium (with legal involvement)
```

### KEY MANAGEMENT IMPLICATIONS BY SCENARIO

#### **Scenario A: Planned Transition (30+ Days)**

```
PHASE 1: PREPARATION (Weeks 1-2)
├─ PI notifies current lab of transition date
├─ PI identifies new biostat lab
├─ New lab signs Data Processing Agreement
├─ New lab infrastructure prepared
├─ Timeline: Data transfer planned for Week 4

PHASE 2: FINAL EXPORTS FROM OLD LAB (Week 3)
├─ Current lab completes all outstanding analyses
├─ Final reports generated
├─ Current lab exports all project data to PI
├─ Verification: PI confirms all data received
├─ Audit trail: "Old_Lab @ [date] FINAL_EXPORT complete"

PHASE 3: KEY TRANSITION (Week 4)
Master Key Scenario:
  If Old Lab HELD Master Key:
    ├─ Old lab decrypts database
    ├─ Site generates unencrypted CSV export
    ├─ New lab receives CSV (no encryption key)
    ├─ New lab optionally re-encrypts with their key
    └─ Old lab deletes all copies (contract requirement)

PHASE 4: NEW LAB ONBOARDING (Week 4-5)
├─ New lab receives exported dataset
├─ New lab sets up analysis environment
├─ New lab begins independent analysis verification
├─ Parallel run: Both labs may work for 2 weeks (validation)
├─ Old lab archive: Deactivate, no further access
└─ Audit trail: "New_Lab @ [date] RECEIVED_DATA & BEGIN_ANALYSIS"

PHASE 5: SIGN-OFF & AUDIT (Week 6)
├─ PI reviews analyses from both labs (reconciliation)
├─ Any discrepancies identified and resolved
├─ Old lab access formally revoked
├─ New lab confirms data integrity
├─ Regulatory audit trail complete
```

**Audit Trail Entry**:
```
2025-06-01 09:00:00 | ACTION: BIOSTAT_LAB_TRANSITION_PLANNED
                    | OLD_LAB: AnalysisCorp Inc.
                    | NEW_LAB: StatMasters Analytics
                    | TRANSITION_DATE: 2025-06-30
                    | AUTHORIZED_BY: PI_Dr_JohnSmith

2025-06-30 14:00:00 | ACTION: OLD_LAB_FINAL_EXPORT
                    | OLD_LAB: AnalysisCorp Inc.
                    | DATA_RECORDS: 250 subjects, 15,000 forms
                    | VERIFIED_BY: PI_Dr_JohnSmith

2025-07-01 08:00:00 | ACTION: NEW_LAB_DATA_RECEIVED
                    | NEW_LAB: StatMasters Analytics
                    | DATA_RECORDS: 250 subjects, 15,000 forms
                    | VERIFIED_BY: NEW_LAB_Director

2025-07-01 15:00:00 | ACTION: OLD_LAB_ACCESS_REVOKED
                    | REASON: Transition complete
                    | AUTHORIZATION: PI_Dr_JohnSmith
                    | TIMESTAMP: 2025-07-01 15:30 UTC
```

**Master Key Strategy**:
- ✅ Site (or original holder) retains master key throughout
- ✅ Old lab exports plaintext CSV
- ✅ New lab gets CSV only (not key)
- ✅ No key transfer needed
- ✅ Clean separation of responsibilities

---

#### **Scenario B: Urgent Transition (7-14 Days)**

```
PHASE 1: EMERGENCY DECISION (Day 1)
├─ PI decides immediately to change labs
├─ Reason: Lab failing to meet timeline, poor responsiveness
├─ New lab identified (may be replacement from vendor)
├─ Current contract: 30 days notice clause (may need waiver)
└─ Legal review: Can we exit early?

PHASE 2: DATA HANDOFF (Days 2-5)
├─ All outstanding analyses stopped
├─ Current lab submits all work-in-progress
├─ Final export: "All data as of [date]"
├─ Verification meeting (video call)
├─ Confirmed: PI has all data exports

PHASE 3: NEW LAB RAMP-UP (Days 5-10)
├─ New lab receives data urgently
├─ New lab rebuilds analysis from scratch
├─ Parallel validation: Verify old lab's preliminary results
├─ Resolve discrepancies (if any)
└─ New lab proceeds with analysis independently

PHASE 4: TRANSITION COMPLETE (Day 14)
├─ Old lab final invoice & contract closure
├─ Old lab: All ZZedc access revoked immediately
├─ Audit trail: Complete, documented, signed
└─ New lab: Full analysis responsibility
```

**Risk Management**:
```
Risk: Lost work-in-progress from old lab
├─ Mitigation: Require all files in .csv or .R format
├─ Backup: PI keeps copies of all exports
└─ Recovery: New lab can regenerate analyses from data

Risk: Analysis discrepancies between labs
├─ Mitigation: Parallel validation period
├─ Resolution: Meet to resolve methodology differences
└─ Documentation: Explain any differences in final report

Risk: Data integrity concerns
├─ Mitigation: Checksums of exported data
├─ Verification: New lab confirms data completeness
└─ Audit: Hash comparison old vs new
```

**Master Key Strategy**:
- ✅ If Site holds key: Site exports data, no key transfer
- ✅ If Old Lab holds key: Old Lab exports & revokes access immediately
- ✅ New Lab gets data export only
- ✅ Key revocation: Within 24 hours of handoff
- ✅ Audit trail: Hourly access logs during transition

---

#### **Scenario C: Emergency - Lab Out of Business (1-3 Days)**

```
CRITICAL ISSUE: Lab goes out of business IMMEDIATELY
├─ Lab: Bankruptcy, office closed, staff unavailable
├─ Data: Unknown state (may be lost)
├─ Key: If lab held key, database potentially inaccessible
└─ Timeline: URGENT (hours matter)
```

**Scenario C.1: Site Held Master Key (Best Case)**

```
DAY 1: ASSESSMENT
├─ Lab closes immediately
├─ PI confirms: Site has backup of all exports
├─ Verify: Last successful export was [date]
├─ Assessment: PI has all raw data needed

DAY 2: RECOVERY
├─ PI accesses ZZedc with master key (site held)
├─ Confirms all data present in encrypted database
├─ Generates fresh export for new lab
├─ Verifies database integrity (checksum validation)

DAY 3: NEW LAB ONBOARDING
├─ New lab receives complete data export
├─ New lab begins analysis from scratch
├─ No data loss: All original data preserved
└─ Recovery: Minimal

Result: ✅ DATA PRESERVED (Site held key)
```

**Scenario C.2: Lab Held Master Key (Worst Case)**

```
CRITICAL: Lab held master key, lab is now unavailable
├─ Problem: Database encrypted, key may be lost
├─ Lab staff: Unreachable (business closed)
├─ Access: Cannot decrypt database without key
└─ Timeline: 24-48 hours before data considered lost

RECOVERY OPTIONS:

Option 1: Contact Lab Creditors/Receiver
├─ Lab's assets in receivership
├─ Try to contact receiver to retrieve key
├─ Legal process: Slow (days-weeks)
├─ Success rate: Low
└─ NOT RECOMMENDED for emergency

Option 2: Key Escrow Backup
├─ (If lab had escrow key backup)
├─ Escrow agent releases key copy
├─ Access restored within hours
├─ Requires: Lab planned for this scenario
└─ BEST PRACTICE (but rare in practice)

Option 3: Restore from Backup
├─ If lab had unencrypted backups
├─ Restore to previous date
├─ Data loss: Since last backup
├─ Requires: Lab cooperation (unavailable)
└─ RISKY

Option 4: Accept Data Loss
├─ Lab inaccessible, key lost
├─ Database unreadable without key
├─ Data loss: All data since backup
├─ Recovery: Impossible
├─ Regulatory: GDPR violation (data loss)
└─ CATASTROPHIC

Result: ❌ DATA LOSS LIKELY (Lab held key)
```

**CRITICAL LESSON**:
```
Never let external lab hold master encryption key
├─ Risk: Lab closure = data loss
├─ Regulatory: GDPR violation
├─ Recovery: No options
└─ Prevention: Site or sponsor always holds master key
```

---

#### **Scenario D: Security Incident - Data Breach Suspected (IMMEDIATE)**

```
ALERT: Lab discovers potential data breach
├─ Incident: Unauthorized access suspected
├─ Data: May have been compromised
├─ Response: Immediate access revocation required
└─ Timeline: Hours matter (regulatory notification deadline)
```

**IMMEDIATE ACTIONS (Hour 0-4)**:

```
Step 1: Revoke Lab Access (Hour 0-1)
├─ Site/Sponsor: IMMEDIATELY revoke lab credentials
├─ Database: Revoke API access, database user, VPN access
├─ Cloud: If using AWS, revoke all IAM permissions
├─ Audit: Log all access points revoked with timestamp
├─ Result: Lab CAN NO LONGER ACCESS ANY DATA

Step 2: Secure Backup & Archive (Hour 1-2)
├─ Site/Sponsor: Create encrypted backup of database
├─ Copy location: Secure offline or separate AWS account
├─ Verify: Hash/checksum integrity confirmed
├─ Lock: Backup made read-only, tamper-evident
└─ Goal: Preserve evidence for investigation

Step 3: Investigation & Assessment (Hour 2-4)
├─ Questions:
│  ├─ What data accessed? (Check audit logs)
│  ├─ When was access? (Timestamp range)
│  ├─ Who accessed? (User ID / IP address)
│  ├─ Was encryption broken? (Lab still holds key?)
│  └─ What's the scope of exposure?
├─ Audit trail review:
│  ├─ Lab's database queries (last 30 days)
│  ├─ Lab's key access (if applicable)
│  ├─ Suspicious activity patterns
│  └─ Timeline of breach discovery
└─ Legal consultation: What are our obligations?
```

**Master Key Implications**:

```
If Site/Sponsor HELD Master Key:
  ✅ Advantage: Lab never had key
  ✅ Lab could read plaintext data (if they queried)
  ✅ Lab could NOT decrypt encrypted database directly
  ✅ Risk: Limited to what lab was authorized to access
  ✅ Recovery: Revoke API access, data remains encrypted
  └─ Action: REVOKE ACCESS immediately

If Lab HELD Master Key:
  ❌ Major Problem: Lab has encryption key
  ❌ Lab can decrypt entire database independently
  ❌ Lab can access all data including other sites' data
  ❌ Revoking API access doesn't protect encrypted database
  ❌ Unless: We change master key (requires decryption/re-encryption)
  └─ Action: CHANGE MASTER KEY (emergency procedure)
```

**EMERGENCY KEY ROTATION PROCEDURE**:

```
Step 1: Assume Breach (Lab may have stolen key)
├─ Current Key: COMPROMISED (lab might have copy)
├─ New Key: MUST BE GENERATED
└─ Action: Cannot trust current key security

Step 2: Generate New Master Key
├─ Generate new 256-bit random key
├─ Store in secure location (AWS KMS or HSM)
├─ Do NOT use on same system lab had access to
└─ Keep old key in secure escrow (legal requirements)

Step 3: Re-encrypt Database (CRITICAL)
├─ Decrypt entire database with OLD key (may be breached)
├─ Re-encrypt with NEW key (not compromised)
├─ Timeline: Hours to days depending on database size
├─ Downtime: Database unavailable during re-encryption
└─ Risk: Large databases may take long time

Step 4: Audit Trail of Key Rotation
├─ Document:
│  ├─ Breach detection time
│  ├─ Old key REVOKED time
│  ├─ New key GENERATED time
│  ├─ Re-encryption START time
│  ├─ Re-encryption COMPLETE time
│  ├─ Lab access REVOKED time
│  └─ Verification of data integrity
├─ Sign: By authorized officer (PI, DM, CRO)
└─ Archive: For FDA/GDPR investigation
```

**REGULATORY NOTIFICATION**:

```
GDPR Article 33 (Breach Notification):
├─ Timeline: Within 72 hours to Data Protection Authority
├─ Include:
│  ├─ What data accessed (subjects, forms, fields)
│  ├─ How many people affected
│  ├─ Date of breach discovery
│  ├─ What we did to contain it
│  ├─ What we recommend to subjects
│  └─ Your contact for follow-up
├─ If no risk: May not need to notify subjects
└─ If high risk: Notify all affected subjects

FDA 21 CFR Part 312.32 (Safety Report):
├─ If breach involved safety data (AE, lab results)
├─ Must report to FDA within 7 days (serious)
├─ Include: Data integrity verification
├─ Include: Remediation steps taken
└─ Timeline: URGENT
```

**Audit Trail Entry (Post-Breach)**:
```
2025-08-15 14:30:00 | ALERT: POTENTIAL_DATA_BREACH_DETECTED
                    | LAB: AnalysisCorp Inc.
                    | DISCOVERED_BY: Lab Security Team (lab-initiated notification)
                    | REPORTED_TO: PI_Dr_JohnSmith @ 14:32
                    | REPORTED_TO: CRO_DataSecurityOfficer @ 14:35

2025-08-15 14:45:00 | ACTION: LAB_ACCESS_REVOKED
                    | SCOPE: All database access, API tokens, VPN, SFTP
                    | TIMESTAMP: 2025-08-15 14:45:00 UTC
                    | AUTHORIZED_BY: CRO_DataSecurityOfficer
                    | REASON: Suspected data breach

2025-08-15 15:30:00 | ACTION: DATABASE_BACKUP_CREATED
                    | PURPOSE: Evidence preservation
                    | LOCATION: Secure offline storage
                    | HASH: [SHA-256 checksum for integrity]
                    | AUTHORIZED_BY: CRO_TechDirector

2025-08-16 10:00:00 | ACTION: INVESTIGATION_REPORT_COMPLETED
                    | FINDINGS:
                    │  ├─ Lab accessed: 250 subjects, basic demographics
                    │  ├─ Lab accessed: Baseline labs (no safety data)
                    │  ├─ Unauthorized access: 3 subjects not authorized for lab
                    │  ├─ Encryption intact: Database never decrypted by lab
                    │  └─ Key exposure: Unknown (assume compromised)
                    | RISK_LEVEL: Medium (limited PII, no safety data)
                    | NOTIFICATION_REQUIRED: Yes (GDPR Article 33)

2025-08-17 00:00:00 | ACTION: MASTER_KEY_ROTATION_INITIATED
                    | OLD_KEY: REVOKED (assumed compromised)
                    | NEW_KEY: GENERATED (256-bit random)
                    | RE_ENCRYPTION_START: 2025-08-17 02:00 UTC
                    | ESTIMATED_DURATION: 8 hours (250 GB database)
                    | AUTHORIZED_BY: CRO_ChiefSecurityOfficer

2025-08-17 10:30:00 | ACTION: RE_ENCRYPTION_COMPLETE
                    | DATABASE: Now encrypted with NEW key only
                    | VERIFICATION: Integrity checks passed
                    | DATA_INTEGRITY: 100% confirmed
                    | AUTHORIZED_BY: CRO_TechDirector

2025-08-17 11:00:00 | ACTION: REGULATORY_NOTIFICATION_SENT
                    | TO: EU Data Protection Authority (DPA)
                    | INCIDENT: Unauthorized access at contractor
                    | SUMMARY: Lab breach, limited PII exposed, encryption remained intact
                    | STATUS: Notified within 72 hours (GDPR Article 33 compliant)

2025-08-18 09:00:00 | ACTION: INVESTIGATION_CLOSED
                    | CAUSE: Lab security vulnerability (unpatched system)
                    | REMEDIATION: Lab contract terminated, new lab selected
                    | FUTURE: Enhanced security requirements for new lab
                    | DOCUMENTATION: Complete file in CRO legal archive
```

**Master Key Lesson**:
```
✅ BEST PRACTICE:
   Site or Sponsor holds master key always
   └─ Prevents lab from holding decryption capability
   └─ Enables rapid access revocation
   └─ Allows emergency key rotation
   └─ Maintains regulatory control

❌ AVOID:
   Lab holds master key
   └─ Lab breach = compromised encryption
   └─ Cannot revoke database access (lab has key)
   └─ Forces emergency key rotation (major operation)
   └─ Regulatory nightmare (loss of control)
```

---

### CRISIS MANAGEMENT SUMMARY

| Scenario | Risk Level | Key Holder | Recovery Time | Data Loss Risk |
|----------|-----------|-----------|----------------|---|
| Planned Transition | Low | Site ✅ | 2-4 weeks | None |
| Urgent Transition | Medium | Site ✅ | 1-2 weeks | Low |
| Lab Bankruptcy | High/Critical | Site ✅ | Days | None |
| Lab Bankruptcy | Critical ❌ | Lab ❌ | Weeks+ | Catastrophic |
| Data Breach (Site Key) | Medium | Site ✅ | Days | None |
| Data Breach (Lab Key) | Critical | Lab ❌ | Days+ | Possible |

---

## DECISION REQUIRED FROM USER

Before implementing Feature #1, please confirm:

1. **Does Feature #1 design align** with these three scenarios?
   - Pharma: Sponsor holds master key
   - Academic: DCC holds master key
   - Single-Site: Site holds master key (or dual-key with lab)

2. **Should Feature #1 support export functionality**?
   - Yes: Create secure export capability (CSV with audit trail)
   - No: Defer to later feature (users will request)

3. **Should Feature #1 include AWS KMS integration**?
   - Phase 1: Support environment variable only
   - Phase 1: Include AWS KMS option (code path for production)
   - Defer: Only support environment variable initially

4. **Should audit trail log every key access**?
   - Yes: Every decryption operation logged
   - No: Only log at startup/shutdown
   - Recommendation: Yes (required for FDA/GDPR)

---

**Ready to proceed with Feature #1 implementation?**

Once approved, we'll implement:
- ✅ SQLCipher integration
- ✅ Master key generation
- ✅ Environment variable storage
- ✅ AWS KMS path (option, not required)
- ✅ Export functionality
- ✅ Audit logging
- ✅ Documentation for all three scenarios

