# Data Directory

This directory contains all the Excel data files for the Order Processing Application.

## Files

- **login_details.xlsx** - User login credentials and authentication information
  - Columns: LoginDetailsId, Username, Password, DisplayName, IsActive, CreatedOn, ModifiedOn

- **orders.xlsx** - Order information including order numbers and associated machines
  - Columns: OrderId, OrderNumber, Machine, Status, CreatedOn, ModifiedOn, CreatedBy, ModifiedBy

- **hour_registration.xlsx** - Time tracking records for orders
  - Columns: HourRegistrationId, OrderId, UserId, StartTime, EndTime, ElapsedTime, IsActive, CreatedOn, ModifiedOn

## Notes

- These files are automatically created when you first run the app
- You can edit these files directly in Excel if needed
- The app will read from and write to these files automatically
- Make sure to close the app before editing the files manually

