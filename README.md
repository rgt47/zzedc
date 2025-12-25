# ZZedc - Electronic Data Capture System

<!-- badges: start -->
<!-- badges: end -->

The `zzedc` package provides a Shiny application for electronic data capture (EDC) in clinical trials and research studies, implemented using Bootstrap 5 components via bslib.

## System Features

- **Authentication system**: Role-based user access with credential management
- **Data entry interface**: Customizable forms with automated validation
- **Reporting functionality**: Data summarization, quality control metrics, and statistical reports
- **Data management**: Interactive data visualization, filtering, and subset extraction
- **Data export**: Multiple export formats including CSV, Excel, JSON, PDF, and HTML
- **User interface**: Responsive design compatible with desktop and mobile devices
- **Data validation**: Real-time validation with immediate user feedback

## Installation

You can install the development version of zzedc from [GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("rythomas/zzedc")
```

## Usage

To launch the interactive EDC application:

```r
library(zzedc)
launch_zzedc()
```

The application will open in your default web browser with the following interface components:

1. **Home**: Welcome dashboard with system overview and status indicators
2. **EDC**: Data entry forms with user authentication and access control
3. **Reports**: Reporting system including:
   - Basic data summaries
   - Data quality metrics
   - Statistical analysis with interactive tables
4. **Data Explorer**: Data management capabilities including:
   - File upload and processing
   - Missing data analysis
   - Interactive visualizations
5. **Export Center**: Data export functionality including:
   - Multiple format support
   - Batch export operations
   - Export templates and scheduling

## Default Credentials

For testing purposes (change before production deployment):

- Username: `ww`, Password: `pw`
- Username: `q`, Password: `pw`
- Username: `w`, Password: `pw`

## Application Architecture

### Technology Stack

- **UI Framework**: `bslib` (Bootstrap 5) with `bsicons`
- **Data Tables**: `DT` with filtering and sorting capabilities
- **Visualizations**: `ggplot2` and `plotly` for interactive visualizations
- **Authentication**: Custom secure login system
- **Data Storage**: File-based storage with SQLite support

### Package Structure

```
zzedc/
   DESCRIPTION              # Package metadata
   NAMESPACE               # Generated namespace
   README.md               # This file
   R/                      # Package functions
      launch_zzedc.R      # Main launcher function
      zzedc-package.R     # Package documentation
   ui.R                    # Bootstrap 5 user interface
   server.R                # Server logic
   global.R                # Global settings
   home.R                  # Home page components
   edc.R                   # EDC form logic
   auth.R                  # Authentication system
   savedata.R              # Data persistence
   report[1-3].R           # Report modules
   data.R                  # Data explorer
   export.R                # Export functionality
   forms/                  # Form definitions
   www/                    # Web assets
   tests/                  # Test suite
   credentials/            # User credentials
```

## Technical Implementation

This implementation incorporates modern R/Shiny development patterns including:

### User Interface Design
- Bootstrap 5 components for responsive layouts
- Modern card-based design patterns
- Consistent iconography using bsicons
- Value boxes for key metrics display
- Mobile-compatible responsive design

### Software Architecture
- Proper R package structure with DESCRIPTION file
- Roxygen2 documentation for all functions
- Modular code organization following R package best practices
- Explicit NAMESPACE with package imports
- Comprehensive test suite with testthat

### System Capabilities
- Full-screen expandable interface components
- Advanced data table functionality with DT
- Interactive tooltips and user interface elements
- Professional color schemes and typography
- Export templates and batch operations

## Example Workflow

1. Launch the application with `launch_zzedc()`
2. Login with appropriate user credentials
3. Navigate to the EDC tab for data entry
4. Use the Reports tab to monitor data quality
5. Access the Data Explorer for data management
6. Export results using the Export Center

## Dependencies

This package builds on several R packages:

- `shiny` - Web application framework
- `bslib` - Bootstrap 5 theming and components
- `bsicons` - Bootstrap icon library
- `DT` - Interactive data tables
- `ggplot2` and `plotly` - Data visualization
- `dplyr` - Data manipulation
- `jsonlite` - JSON processing

## Regulatory Compliance

ZZedc includes frameworks for regulatory compliance:

- **GDPR**: Data subject rights, consent management, audit logging
- **21 CFR Part 11**: Electronic signatures, audit trails, access controls

See `vignette("regulatory-compliance-whitepaper")` for details.

## Documentation

- `vignette("quickstart")` - Quick start guide
- `vignette("getting-started")` - Detailed setup
- `vignette("small-project-guide")` - 10-50 participants
- `vignette("medium-project-guide")` - 50-500 participants
- `vignette("advanced-features")` - Custom development

## Reproducibility

This package is developed using the zzcollab framework for reproducible
research. To reproduce the development environment:

```bash
git clone https://github.com/rgt47/zzedc.git
cd zzedc
make r  # Enter Docker container with all dependencies
```

## Contributing

Please report issues at: https://github.com/rgt47/zzedc/issues

## License

GPL-3

## Author

Ronald (Ryy) G. Thomas (rgthomas@ucsd.edu)
