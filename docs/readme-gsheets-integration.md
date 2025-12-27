# ZZedc Google Sheets Integration - Complete System

## Overview

ZZedc now includes **full integration** with Google Sheets, allowing users to configure authentication, roles, and data dictionary through familiar Google Sheets interface instead of R programming. This makes ZZedc accessible to non-technical clinical research teams.

## 🎯 What's New

### ✅ Fully Integrated Features

1. **Google Sheets Configuration**
   - Define users, roles, and sites in Google Sheets
   - Create data dictionary and forms in Google Sheets
   - Automatic database generation from sheets

2. **Enhanced User Interface**
   - New "Setup" tab for Google Sheets management
   - Dynamic form loading from Google Sheets
   - Forms overview with management tools
   - Integrated setup wizard

3. **Seamless Integration**
   - Automatic detection of Google Sheets vs traditional setup
   - Fallback to traditional forms if no Google Sheets found
   - Unified authentication system
   - Compatible with all existing ZZedc features

4. **Advanced Form Generation**
   - Real-time form creation from Google Sheets
   - Complete validation system
   - Conditional field logic
   - Multi-visit form support

## 🚀 Quick Start

### Option 1: Enhanced Launch (Recommended)
```r
source("run_enhanced_app.R")
```

### Option 2: Setup from Google Sheets
```r
source("setup_from_gsheets.R")
setup_zzedc_from_gsheets_complete(
  auth_sheet_name = "your_auth_sheet",
  dd_sheet_name = "your_data_dictionary",
  project_name = "my_study"
)
```

### Option 3: Interactive Setup Menu
```r
source("setup_menu.R")  # Opens interactive menu
```

## 📁 File Structure

### Core Integration Files
```
zzedc/
├── gsheets_integration.R          # Main Google Sheets functions
├── gsheets_auth_builder.R         # Authentication system builder
├── gsheets_dd_builder.R           # Data dictionary builder
├── gsheets_form_loader.R          # Dynamic form loading
├── gsheets_ui_integration.R       # UI enhancement
├── gsheets_server_integration.R   # Server enhancement
├── setup_from_gsheets.R           # Complete setup orchestration
└── setup_menu.R                   # Interactive setup interface
```

### Enhanced Launch Files
```
├── ui_enhanced.R                  # Enhanced UI with Google Sheets
├── server_enhanced.R              # Enhanced server logic
├── run_enhanced_app.R             # Enhanced launch script
└── README_GSHEETS_INTEGRATION.md  # This file
```

### Generated Files (created by setup)
```
├── forms_generated/               # Auto-generated form files
│   ├── demographics_form.R
│   ├── vitals_form.R
│   └── validation_rules.R
├── launch_[project_name].R        # Custom launch script
└── config.yml                     # Updated configuration
```

## 🛠 Setup Methods

### 1. Google Sheets Setup (Non-technical users)

**Step 1: Create Google Sheets**
- Authentication sheet with users, roles, sites
- Data dictionary sheet with forms and field definitions

**Step 2: Run setup**
```r
source("setup_from_gsheets.R")
setup_zzedc_from_gsheets_complete()
```

**Step 3: Launch**
```r
source("run_enhanced_app.R")
```

### 2. Interactive Setup Menu

```r
source("setup_menu.R")
# Follow the interactive prompts
```

### 3. Traditional Setup (R programmers)

Still fully supported - the system automatically detects and uses traditional setup if no Google Sheets configuration is found.

## 🎮 User Interface Changes

### New Navigation Tabs

1. **Dynamic Form Tabs** - One tab per Google Sheets form
2. **Forms Overview** - Management and status of all forms
3. **Setup Tab** - Configuration management interface

### Enhanced Features

- **In-app Google Sheets refresh** - Update forms without restarting
- **Setup verification** - Check system integrity
- **Configuration export** - Backup current settings
- **Progress indicators** - Visual setup progress
- **Error handling** - User-friendly error messages

## 📊 Google Sheets Structure

### Authentication Sheet (`zzedc_auth`)

**Tab: users**
```csv
username,password,full_name,email,role,site_id,active
admin,admin123,System Admin,admin@study.com,Admin,1,1
jsmith,password123,John Smith,jsmith@study.com,PI,1,1
```

**Tab: roles**
```csv
role,description,permissions
Admin,Full system access,all
PI,Principal Investigator,read_write
Coordinator,Research Coordinator,read_write
```

**Tab: sites**
```csv
site_id,site_name,site_code,active
1,Main Hospital,MH,1
2,Regional Clinic,RC,1
```

### Data Dictionary Sheet (`zzedc_data_dictionary`)

**Tab: forms_overview**
```csv
workingname,fullname,visits
demographics,Demographics Form,baseline
vitals,Vital Signs,baseline,month3,month6
```

**Tab: form_demographics**
```csv
field,prompt,type,layout,req,values,valid,validmsg
subject_id,Subject ID,C,text,1,,,
age,Age (years),N,numeric,1,,age>=18,Age must be 18+
gender,Gender,L,radio,1,male:female,,
```

## 🔧 Advanced Configuration

### Custom Database Location
```r
setup_zzedc_from_gsheets_complete(
  db_path = "custom/path/study.db"
)
```

### Custom Validation Rules
```csv
field,valid,validmsg
weight,weight > 0 && weight < 500,Weight must be 0-500kg
email,grepl("@", email),Please enter valid email
```

### Conditional Fields
```csv
field,cond
pregnancy_test,gender=female
```

## 🔒 Security Features

- **Secure password hashing** with customizable salt
- **Role-based access control** from Google Sheets
- **Session management** and timeout
- **Audit trail** for all data changes
- **Database connection pooling** for performance

## 📈 Compatibility

### ✅ Fully Compatible With:
- All existing ZZedc reports
- Data export functionality
- Quality control features
- User authentication system
- Database structure
- R package ecosystem

### 🔄 Migration Support:
- **Traditional → Google Sheets**: Export current setup to sheets
- **Google Sheets → Traditional**: Database remains compatible
- **Between projects**: Import/export database files

## 🚨 Troubleshooting

### Common Issues

1. **"Google Sheets not found"**
   - Check sheet names match exactly
   - Verify Google account has access
   - Re-authenticate: `gs4_auth()`

2. **"Forms not loading"**
   - Run setup verification in Setup tab
   - Check `forms_generated/` directory exists
   - Restart application after setup changes

3. **"Database errors"**
   - Verify database file permissions
   - Check SQLite installation
   - Review database path in config.yml

### Debug Mode
```r
options(shiny.trace = TRUE)
source("run_enhanced_app.R")
```

## 📚 Documentation

- **`GSHEETS_SETUP_GUIDE.md`** - Detailed Google Sheets setup guide
- **`ZZEDC_USER_GUIDE.md`** - Complete user manual
- **Setup tab in app** - In-app help and documentation links

## 🎯 Benefits of Integration

### For Non-Technical Users:
- **No R programming required**
- **Familiar Google Sheets interface**
- **Easy collaboration** on form design
- **Version control** through Google Sheets history

### For Technical Users:
- **All original functionality preserved**
- **Enhanced configuration options**
- **Automated setup processes**
- **Better error handling and validation**

### For Clinical Research Teams:
- **Faster study setup**
- **Easier form modifications**
- **Better team collaboration**
- **Reduced IT dependency**

## 🚀 Getting Started Checklist

- [ ] 1. Create Google Sheets with required structure
- [ ] 2. Run `source("run_enhanced_app.R")`
- [ ] 3. Navigate to Setup tab if needed
- [ ] 4. Configure Google Sheets integration
- [ ] 5. Start data entry in generated forms

The system is now **fully integrated** - Google Sheets configuration works seamlessly alongside all existing ZZedc features!