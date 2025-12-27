# ADHD Clinical Trial - ZZedc Workflow Guide

## Trial Overview
**Study**: Efficacy of Novel ADHD Medication vs. Placebo
**Design**: Randomized, double-blind, placebo-controlled trial
**Duration**: 12 weeks with 4 assessment visits
**Sample Size**: 60 participants (30 per group)
**Primary Endpoint**: ADHD Rating Scale improvement at Week 12

## Team Roles & Responsibilities

### 👨‍🔬 **Dr. Sarah Chen - Principal Investigator**
- **Role**: Study oversight, protocol compliance, data review
- **Technical Level**: Basic computer skills
- **ZZedc Access**: Full administrative access, reports review
- **Responsibilities**:
  - Final approval of study setup
  - Weekly data quality reviews
  - Regulatory compliance oversight
  - Safety monitoring

### 👩‍💻 **Alex Rodriguez - Graduate Student (Biostatistics)**
- **Role**: Technical lead, database administrator
- **Technical Level**: Advanced R programming, database management
- **ZZedc Access**: Full system administration
- **Responsibilities**:
  - Initial system setup and configuration
  - Google Sheets creation and management
  - Data quality assurance
  - Statistical analysis preparation

### 👩‍⚕️ **Maria Santos - Psychometrist**
- **Role**: Patient recruitment, data collection, data entry
- **Technical Level**: Moderate computer skills, clinical assessment expertise
- **ZZedc Access**: Data entry and patient management
- **Responsibilities**:
  - Patient screening and enrollment
  - Clinical assessments and data collection
  - Daily data entry into ZZedc
  - Basic data verification

---

## Phase 1: Initial Setup (Week -2)

### **Alex's Tasks - Technical Setup**

#### Step 1: ZZedc Installation and Configuration
```r
# 1. Set up ZZedc environment
setwd("/Users/alex/ADHD_Trial/")
source("run_enhanced_app.R")  # Launch enhanced ZZedc
```

#### Step 2: Create Google Sheets Configuration

**Create Authentication Sheet: `ADHD_Trial_Auth`**

**Tab: `users`**

| username | password | full_name | email | role | site_id | active |
|----------|----------|-----------|-------|------|---------|--------|
| drschen | adhd2024! | Dr. Sarah Chen | schen@university.edu | PI | 1 | 1 |
| alex_r | biostat123 | Alex Rodriguez | arodriguez@university.edu | Admin | 1 | 1 |
| maria_s | psych456 | Maria Santos | msantos@university.edu | Coordinator | 1 | 1 |
| backup_admin | backup789 | Backup Admin | backup@university.edu | Admin | 1 | 0 |

**Tab: `roles`**

| role | description | permissions |
|------|-------------|-------------|
| Admin | Full system access | all |
| PI | Principal Investigator - can view all data and reports | read_write |
| Coordinator | Research Coordinator - data entry and patient management | read_write |
| Analyst | Data analyst - reports only | read_only |

**Tab: `sites`**

| site_id | site_name | site_code | active |
|---------|-----------|-----------|--------|
| 1 | University Psychology Clinic | UPC | 1 |

**Create Data Dictionary Sheet: `ADHD_Trial_DataDict`**

**Tab: `forms_overview`**

| workingname | fullname | visits |
|-------------|----------|--------|
| screening | Screening & Enrollment | screening |
| demographics | Demographics | baseline |
| medical_history | Medical History | baseline |
| adhd_rating | ADHD Rating Scale | baseline,week4,week8,week12 |
| conners_adult | Conners Adult ADHD Rating Scale | baseline,week4,week8,week12 |
| side_effects | Side Effects Checklist | week4,week8,week12 |
| vital_signs | Vital Signs | baseline,week4,week8,week12 |
| medication_compliance | Medication Compliance | week4,week8,week12 |
| adverse_events | Adverse Events | baseline,week4,week8,week12 |
| study_completion | Study Completion | week12 |

**Tab: `form_screening`**

| field | prompt | type | layout | req | values | cond | valid | validmsg |
|-------|--------|------|--------|-----|--------|------|-------|----------|
| subject_id | Subject ID | C | text | 1 | | | length(subject_id) == 7 | Subject ID must be exactly 7 characters |
| screening_date | Screening Date | D | date | 1 | | | screening_date <= today() | Screening date cannot be in future |
| age | Age (years) | N | numeric | 1 | | | age >= 18 && age <= 65 | Age must be 18-65 years |
| gender | Gender | L | radio | 1 | Male:Female:Other | | | |
| inclusion_adhd | Meets ADHD criteria? | L | radio | 1 | Yes:No | | | |
| inclusion_age | Age 18-65? | L | radio | 1 | Yes:No | | | |
| inclusion_consent | Informed consent signed? | L | radio | 1 | Yes:No | | | |
| exclusion_pregnancy | Currently pregnant? | L | radio | 1 | Yes:No | gender=='Female' | | |
| exclusion_medication | Taking excluded medications? | L | radio | 1 | Yes:No | | | |
| exclusion_psychosis | History of psychosis? | L | radio | 1 | Yes:No | | | |
| eligible | Overall Eligibility | L | radio | 1 | Eligible:Not Eligible | | | |
| randomization_group | Randomization Group | L | radio | 0 | Active:Placebo | eligible=='Eligible' | | |
| notes | Screening Notes | C | textarea | 0 | | | | |

**Tab: `form_demographics`**

| field | prompt | type | layout | req | values | cond | valid | validmsg |
|-------|--------|------|--------|-----|--------|------|-------|----------|
| subject_id | Subject ID | C | text | 1 | | | length(subject_id) == 7 | Subject ID must be 7 characters |
| visit_date | Visit Date | D | date | 1 | | | | |
| race | Race/Ethnicity | L | select | 1 | White:Black or African American:Asian:Hispanic/Latino:Native American:Other:Prefer not to answer | | | |
| education_years | Years of Education | N | numeric | 1 | | | education_years >= 6 && education_years <= 25 | Education must be 6-25 years |
| employment_status | Employment Status | L | select | 1 | Full-time:Part-time:Student:Unemployed:Disabled:Retired | | | |
| marital_status | Marital Status | L | select | 1 | Single:Married:Divorced:Widowed:Separated | | | |
| household_income | Annual Household Income | L | select | 0 | <$25k:$25k-$50k:$50k-$75k:$75k-$100k:>$100k:Prefer not to answer | | | |
| insurance_type | Insurance Type | L | select | 0 | Private:Medicare:Medicaid:Uninsured:Other | | | |
| emergency_contact_name | Emergency Contact Name | C | text | 1 | | | | |
| emergency_contact_phone | Emergency Contact Phone | C | text | 1 | | | length(emergency_contact_phone) >= 10 | Please enter valid phone number |

**Tab: `form_adhd_rating`**

| field | prompt | type | layout | req | values | cond | valid | validmsg |
|-------|--------|------|--------|-----|--------|------|-------|----------|
| subject_id | Subject ID | C | text | 1 | | | length(subject_id) == 7 | Subject ID must be 7 characters |
| visit_code | Visit | L | select | 1 | baseline:week4:week8:week12 | | | |
| assessment_date | Assessment Date | D | date | 1 | | | | |
| adhd_1 | Often fails to give close attention to details | N | radio | 1 | 0:1:2:3 | | adhd_1 >= 0 && adhd_1 <= 3 | Must select 0-3 |
| adhd_2 | Often has difficulty sustaining attention | N | radio | 1 | 0:1:2:3 | | adhd_2 >= 0 && adhd_2 <= 3 | Must select 0-3 |
| adhd_3 | Often does not seem to listen when spoken to | N | radio | 1 | 0:1:2:3 | | adhd_3 >= 0 && adhd_3 <= 3 | Must select 0-3 |
| adhd_4 | Often does not follow through on instructions | N | radio | 1 | 0:1:2:3 | | adhd_4 >= 0 && adhd_4 <= 3 | Must select 0-3 |
| adhd_5 | Often has difficulty organizing tasks | N | radio | 1 | 0:1:2:3 | | adhd_5 >= 0 && adhd_5 <= 3 | Must select 0-3 |
| adhd_6 | Often avoids tasks requiring sustained attention | N | radio | 1 | 0:1:2:3 | | adhd_6 >= 0 && adhd_6 <= 3 | Must select 0-3 |
| adhd_7 | Often loses things necessary for activities | N | radio | 1 | 0:1:2:3 | | adhd_7 >= 0 && adhd_7 <= 3 | Must select 0-3 |
| adhd_8 | Often easily distracted by extraneous stimuli | N | radio | 1 | 0:1:2:3 | | adhd_8 >= 0 && adhd_8 <= 3 | Must select 0-3 |
| adhd_9 | Often forgetful in daily activities | N | radio | 1 | 0:1:2:3 | | adhd_9 >= 0 && adhd_9 <= 3 | Must select 0-3 |
| adhd_inattention_total | Inattention Subscale Total | N | numeric | 0 | | | adhd_inattention_total >= 0 && adhd_inattention_total <= 27 | Total must be 0-27 |
| adhd_10 | Often fidgets with hands or feet | N | radio | 1 | 0:1:2:3 | | adhd_10 >= 0 && adhd_10 <= 3 | Must select 0-3 |
| adhd_11 | Often leaves seat inappropriately | N | radio | 1 | 0:1:2:3 | | adhd_11 >= 0 && adhd_11 <= 3 | Must select 0-3 |
| adhd_12 | Often runs about or climbs excessively | N | radio | 1 | 0:1:2:3 | | adhd_12 >= 0 && adhd_12 <= 3 | Must select 0-3 |
| adhd_13 | Often has difficulty with quiet activities | N | radio | 1 | 0:1:2:3 | | adhd_13 >= 0 && adhd_13 <= 3 | Must select 0-3 |
| adhd_14 | Often on the go or acts as if driven by motor | N | radio | 1 | 0:1:2:3 | | adhd_14 >= 0 && adhd_14 <= 3 | Must select 0-3 |
| adhd_15 | Often talks excessively | N | radio | 1 | 0:1:2:3 | | adhd_15 >= 0 && adhd_15 <= 3 | Must select 0-3 |
| adhd_16 | Often blurts out answers before questions completed | N | radio | 1 | 0:1:2:3 | | adhd_16 >= 0 && adhd_16 <= 3 | Must select 0-3 |
| adhd_17 | Often has difficulty waiting turn | N | radio | 1 | 0:1:2:3 | | adhd_17 >= 0 && adhd_17 <= 3 | Must select 0-3 |
| adhd_18 | Often interrupts or intrudes on others | N | radio | 1 | 0:1:2:3 | | adhd_18 >= 0 && adhd_18 <= 3 | Must select 0-3 |
| adhd_hyperactive_total | Hyperactivity Subscale Total | N | numeric | 0 | | | adhd_hyperactive_total >= 0 && adhd_hyperactive_total <= 27 | Total must be 0-27 |
| adhd_total_score | Total ADHD Rating Scale Score | N | numeric | 0 | | | adhd_total_score >= 0 && adhd_total_score <= 54 | Total must be 0-54 |

**Tab: `form_side_effects`**

| field | prompt | type | layout | req | values | cond | valid | validmsg |
|-------|--------|------|--------|-----|--------|------|-------|----------|
| subject_id | Subject ID | C | text | 1 | | | length(subject_id) == 7 | Subject ID must be 7 characters |
| visit_code | Visit | L | select | 1 | week4:week8:week12 | | | |
| assessment_date | Assessment Date | D | date | 1 | | | | |
| se_appetite | Decreased appetite | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_insomnia | Sleep problems/insomnia | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_headache | Headache | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_nausea | Nausea | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_dizziness | Dizziness | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_dry_mouth | Dry mouth | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_constipation | Constipation | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_mood_changes | Mood changes/irritability | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_anxiety | Increased anxiety | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_heart_rate | Increased heart rate | L | radio | 0 | None:Mild:Moderate:Severe | | | |
| se_other | Other side effects | C | textarea | 0 | | | | |
| se_any_severe | Any severe side effects? | L | radio | 1 | Yes:No | | | |

#### Step 3: Configure ZZedc System
```r
# Run Google Sheets setup
source("setup_from_gsheets.R")
setup_zzedc_from_gsheets_complete(
  auth_sheet_name = "ADHD_Trial_Auth",
  dd_sheet_name = "ADHD_Trial_DataDict",
  project_name = "ADHD_Clinical_Trial"
)
```

#### Step 4: System Testing
```r
# Launch the configured system
source("launch_ADHD_Clinical_Trial.R")

# Test with each user account:
# Username: alex_r, Password: biostat123
# Username: drschen, Password: adhd2024!
# Username: maria_s, Password: psych456
```

---

## Phase 2: Training & Validation (Week -1)

### **Team Training Session**

#### **For Dr. Chen (PI) - 30 minutes**
1. **System Overview**
   - Navigate to http://localhost:3838
   - Login with username: `drschen`, password: `adhd2024!`
   - Tour of interface: Home, Forms, Reports tabs

2. **Reports Review**
   - Basic Reports: Subject enrollment, completion rates
   - Quality Reports: Data completeness, protocol deviations
   - Statistical Reports: Descriptive statistics, efficacy trends

3. **Safety Monitoring**
   - Navigate to "Adverse Events" form
   - Review side effects data
   - Export procedures for safety reports

#### **For Maria (Psychometrist) - 60 minutes**
1. **Data Entry Training**
   - Login with username: `maria_s`, password: `psych456`
   - Complete practice screening form
   - Practice ADHD Rating Scale entry
   - Learn data validation messages

2. **Patient Management Workflow**
   - Subject ID format: ADHD001, ADHD002, etc.
   - Visit scheduling and tracking
   - Required vs. optional fields

3. **Quality Control**
   - Review entered data before submission
   - Use "Forms Overview" to track completion
   - Handle validation errors

4. **Practice Exercises**
   - Enter 3 mock subjects with complete data
   - Practice different visit types
   - Test error scenarios

#### **For Alex (Technical Lead) - 45 minutes**
1. **Administration Features**
   - User management and permissions
   - Database backup procedures
   - System monitoring

2. **Data Quality Management**
   - Run quality control reports
   - Export data for analysis
   - Handle technical issues

3. **Troubleshooting Common Issues**
   - Password resets
   - Form validation problems
   - Database connectivity

---

## Phase 3: Study Execution (Weeks 1-12)

### **Daily Workflow - Maria (Psychometrist)**

#### **Morning Setup (15 minutes)**
1. **System Check**
   - Navigate to http://localhost:3838
   - Login with credentials
   - Review today's scheduled visits

2. **Patient Schedule Review**
   - Check "Forms Overview" for pending assessments
   - Prepare assessment materials
   - Verify visit windows

#### **Patient Visits (per patient)**

**Screening Visit (45 minutes)**
1. **Pre-Visit**
   - Verify patient identity
   - Confirm informed consent
   - Assign Subject ID (next available: ADHD###)

2. **Data Entry - Screening Form**
   ```
   Navigation: Forms → Screening & Enrollment
   Required Fields:
   - Subject ID: ADHD### (next sequential number)
   - Screening Date: Today's date
   - Age: Patient's age in years
   - Gender: Male/Female/Other
   - All inclusion/exclusion criteria (Yes/No)
   - Notes: Any relevant observations
   ```

3. **Randomization (if eligible)**
   - System will prompt for randomization group
   - Record: Active or Placebo (double-blind maintained)
   - Schedule baseline visit within 7 days

**Baseline Visit (90 minutes)**
1. **Demographics Form**
   ```
   Navigation: Forms → Demographics
   Complete all required fields:
   - Subject ID, Visit Date
   - Race, Education, Employment
   - Emergency contact information
   ```

2. **Medical History Form**
   ```
   Navigation: Forms → Medical History
   Document:
   - Prior ADHD medications
   - Comorbid conditions
   - Current medications
   ```

3. **ADHD Rating Scale**
   ```
   Navigation: Forms → ADHD Rating Scale
   Instructions:
   - Read each item aloud to patient
   - Record 0=Never, 1=Sometimes, 2=Often, 3=Very Often
   - Complete all 18 items
   - System will auto-calculate subscale totals
   ```

4. **Vital Signs**
   ```
   Navigation: Forms → Vital Signs
   Measure and record:
   - Height (cm), Weight (kg)
   - Blood pressure (systolic/diastolic)
   - Heart rate (bpm)
   ```

**Follow-up Visits (Week 4, 8, 12) - 60 minutes each**
1. **ADHD Rating Scale** (repeat baseline procedure)
2. **Side Effects Checklist**
   ```
   Navigation: Forms → Side Effects Checklist
   Review each potential side effect:
   - Rate severity: None/Mild/Moderate/Severe
   - Document any new symptoms
   - Flag any severe side effects for immediate PI review
   ```
3. **Medication Compliance**
4. **Vital Signs**
5. **Adverse Events** (if any)

#### **End-of-Day Procedures (30 minutes)**
1. **Data Review**
   - Navigate to "Forms Overview"
   - Verify all forms completed for today's visits
   - Check for validation errors (red flags)

2. **Quality Check**
   - Review entered data for accuracy
   - Complete any missing fields
   - Add notes for any unusual findings

3. **Communication**
   - Flag urgent issues for Dr. Chen
   - Prepare summary for weekly team meeting

### **Weekly Workflow - Dr. Chen (PI)**

#### **Every Monday (30 minutes)**
1. **Safety Review**
   ```
   Navigation: Reports → Quality Reports
   Review:
   - Any severe adverse events
   - Side effects trends
   - Protocol deviations
   ```

2. **Enrollment Progress**
   ```
   Navigation: Reports → Basic Reports
   Monitor:
   - Total subjects screened
   - Total subjects randomized
   - Completion rates by visit
   ```

3. **Data Quality**
   - Review quality control reports
   - Follow up on any data queries
   - Approve/reject any protocol deviations

### **Bi-weekly Workflow - Alex (Technical Lead)**

#### **Every Other Wednesday (60 minutes)**
1. **System Maintenance**
   ```r
   # Database backup
   file.copy("data/ADHD_Clinical_Trial_gsheets.db",
            paste0("backups/adhd_backup_", Sys.Date(), ".db"))

   # System verification
   source("test_gsheets_setup.R")
   run_all_tests()
   ```

2. **Data Analysis Preparation**
   ```r
   # Export data for analysis
   source("export.R")  # Navigate to Export tab in app
   # Export to CSV for statistical analysis
   ```

3. **Quality Assurance**
   - Run data completeness reports
   - Check for outliers or data entry errors
   - Generate recruitment and retention reports

---

## Phase 4: Data Management & Analysis (Week 13+)

### **Database Lock Preparation - Alex**

#### **Final Data Review (Week 13)**
1. **Data Completeness Check**
   ```r
   # Generate final completeness report
   # Navigate to Reports → Quality Reports
   # Export missing data report
   ```

2. **Query Resolution**
   - Review all data validation flags
   - Resolve outstanding queries with Maria
   - Document all protocol deviations

3. **Database Lock**
   ```r
   # Create final locked database
   file.copy("data/ADHD_Clinical_Trial_gsheets.db",
            "data/ADHD_Trial_LOCKED_FINAL.db")

   # Generate data dictionary for analysis
   # Export complete dataset
   ```

### **Statistical Analysis Preparation**
1. **Data Export**
   ```r
   # Export all forms to CSV
   # Navigation: Export Data → Select All Forms → CSV Format
   ```

2. **Analysis Dataset Creation**
   - Merge forms by Subject ID and Visit
   - Calculate derived variables (ADHD subscale scores)
   - Create analysis-ready datasets

---

## Quality Control Procedures

### **Daily QC Checks - Maria**
- [ ] All required fields completed
- [ ] Visit dates within protocol windows
- [ ] ADHD rating scale items all answered
- [ ] Side effects properly documented
- [ ] Subject ID format consistent (ADHD###)

### **Weekly QC Reviews - Dr. Chen**
- [ ] Safety data reviewed for trends
- [ ] Protocol deviations documented
- [ ] Enrollment targets on track
- [ ] Data quality metrics reviewed

### **System QC Checks - Alex**
- [ ] Database backups completed
- [ ] User access logs reviewed
- [ ] System performance monitored
- [ ] Data validation rules working correctly

---

## Emergency Procedures

### **Severe Adverse Event Protocol**
1. **Immediate Actions (Maria)**
   - Ensure participant safety
   - Document in "Adverse Events" form immediately
   - Set severity to "Severe"
   - Add detailed narrative

2. **Notification (Within 2 hours)**
   - Email Dr. Chen immediately
   - Include Subject ID and event description
   - Dr. Chen reviews within 4 hours

3. **Reporting (Within 24 hours)**
   - Dr. Chen determines reportability
   - Export adverse event data from system
   - Submit required regulatory reports

### **System Technical Issues**
1. **Cannot Access ZZedc**
   - Contact Alex immediately
   - Use paper backup forms if needed
   - Enter data retroactively once system restored

2. **Data Entry Errors**
   - Contact Alex for data correction
   - Document error and correction in notes
   - Never manually edit database files

---

## Success Metrics

### **Operational Metrics**
- **Screening Rate**: Target 2-3 subjects/week
- **Randomization Rate**: Target 75% of screened subjects
- **Retention Rate**: Target >90% completion
- **Data Completeness**: Target >95% complete data

### **Quality Metrics**
- **Data Query Rate**: Target <5% of data points
- **Protocol Deviations**: Target <10% of subjects
- **On-time Visits**: Target >85% within visit windows
- **System Uptime**: Target >99% availability

### **Timeline Milestones**
- **Week 4**: 15 subjects randomized
- **Week 8**: 40 subjects randomized
- **Week 12**: 60 subjects randomized (enrollment complete)
- **Week 16**: All subjects complete Week 12 visit
- **Week 18**: Database lock and analysis begins

---

## Appendices

### **Appendix A: Contact Information**
- **Dr. Sarah Chen (PI)**: schen@university.edu, 555-0101
- **Alex Rodriguez (Technical)**: arodriguez@university.edu, 555-0102
- **Maria Santos (Psychometrist)**: msantos@university.edu, 555-0103
- **IT Support**: itsupport@university.edu, 555-0199

### **Appendix B: System URLs**
- **Production System**: http://localhost:3838
- **Backup System**: http://backup-server:3838
- **Google Sheets**: [Links to authentication and data dictionary sheets]

### **Appendix C: Training Materials**
- ZZedc User Guide: `ZZEDC_USER_GUIDE.md`
- Google Sheets Setup: `GSHEETS_SETUP_GUIDE.md`
- ADHD Rating Scale Manual: `ADHD_Rating_Scale_Manual.pdf`
- Protocol Training Slides: `ADHD_Protocol_Training.pptx`

This workflow ensures efficient, accurate, and compliant data collection for the ADHD clinical trial using the integrated Google Sheets ZZedc system.