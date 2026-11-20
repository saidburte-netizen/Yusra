/// Every user-visible string lives here so Amharic can be added as a second
/// locale map without touching widgets.
abstract final class S {
  // Brand
  static const appName = 'Yusra Pharmacy';
  static const tagline = 'Care made easy';

  // Auth
  static const signIn = 'Sign in';
  static const signOut = 'Sign out';
  static const email = 'Email address';
  static const password = 'Password';
  static const newPassword = 'New password';
  static const confirmPassword = 'Confirm password';
  static const showPassword = 'Show password';
  static const hidePassword = 'Hide password';
  static const forgotPassword = 'Forgot password?';
  static const resetPassword = 'Reset password';
  static const sendResetLink = 'Send reset link';
  static const resetLinkSent = 'Reset link sent. Check your inbox.';
  static const signInToContinue = 'Sign in to continue';
  static const invalidCredentials = 'Email or password is incorrect.';
  static const inactiveAccount =
      'This account is inactive. Please contact your administrator.';
  static const emailRequired = 'Enter your email address.';
  static const emailInvalid = 'Enter a valid email address.';
  static const passwordRequired = 'Enter your password.';
  static const passwordShort = 'Use at least 6 characters.';
  static const passwordsDontMatch = 'Passwords do not match.';
  static const welcomeBack = 'Welcome back';
  static const profile = 'My profile';
  static const changePassword = 'Change password';

  // Shell / navigation
  static const dashboard = 'Dashboard';
  static const pos = 'New sale';
  static const inventory = 'Inventory';
  static const purchasing = 'Purchasing';
  static const sales = 'Sales history';
  static const shifts = 'Shifts';
  static const customers = 'Customers';
  static const prescriptions = 'Prescriptions';
  static const suppliers = 'Suppliers';
  static const expenses = 'Expenses';
  static const reports = 'Reports';
  static const admin = 'Administration';
  static const users = 'Users and roles';
  static const teamAccess = 'Team access';
  static const teamAccessBody =
      'Share your role, branch and published settings with your teammates.';
  static const shareAccess = 'Share my access';
  static const publishSettings = 'Publish settings to team';
  static const editAccess = 'Edit role / branch';
  static const selectTeammates = 'Select teammates';
  static const noTeamMembers = 'No team members found.';
  static const teamShareDone = 'Access shared with the selected teammates.';
  static const settingsPublished = 'Settings published to the whole team.';
  static const accessUpdated = 'Team member access updated.';
  static const branches = 'Branches';
  static const settings = 'Settings';
  static const audit = 'Audit log';
  static const more = 'More';
  static const forbidden = 'Access denied';
  static const signedInAs = 'Signed in as';
  static const roleUnknown = 'unknown';
  static const accountProblem = 'We could not load your account details.';
  static const forbiddenBody = 
      'You do not have permission to open this page. Contact an administrator if you think this is a mistake.';
  static const backToDashboard = 'Back to dashboard';
  static const comingSoon = 'Coming soon';
  static const comingSoonBody =
      'This module is being prepared by another agent and will appear here shortly.';
  static const configurationMissing =
      'Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to the build and reinstall.';

  // Common actions
  static const add = 'Add';
  static const create = 'Create';
  static const edit = 'Edit';
  static const save = 'Save';
  static const cancel = 'Cancel';
  static const delete = 'Delete';
  static const deactivate = 'Deactivate';
  static const reactivate = 'Reactivate';
  static const reset = 'Reset';
  static const search = 'Search';
  static const filter = 'Filter';
  static const exportCsv = 'Export CSV';
  static const exportPdf = 'Export PDF';
  static const refresh = 'Refresh';
  static const close = 'Close';
  static const confirm = 'Confirm';
  static const view = 'View';
  static const all = 'All';
  static const active = 'Active';
  static const inactive = 'Inactive';
  static const yes = 'Yes';
  static const no = 'No';
  static const loading = 'Loading…';
  static const retry = 'Try again';
  static const noData = 'Nothing here yet';
  static const somethingWrong = 'Something went wrong';
  static const saved = 'Saved successfully';
  static const required = 'This field is required.';
  static const optional = 'optional';
  static const confirmDelete = 'Are you sure you want to delete this?';

  // Admin
  static const createUser = 'Create user';
  static const temporaryPassword = 'Temporary password';
  static const copyOnce =
      'Copy this password now — it will not be shown again.';
  static const role = 'Role';
  static const branch = 'Branch';
  static const status = 'Status';
  static const fullName = 'Full name';
  static const teamActivity = 'Team activity';
  static const shiftOpen = 'Shift open';
  static const noShift = 'No open shift';
  static const lastActive = 'Last active';
  static const phone = 'Phone';
  static const pharmacyName = 'Pharmacy name';
  static const taglineLabel = 'Tagline';
  static const address = 'Address';
  static const tin = 'TIN';
  static const licenseNo = 'License number';
  static const currency = 'Currency';
  static const vatRate = 'VAT rate (%)';
  static const lowStockDefault = 'Default low-stock threshold';
  static const expiryAlertDays = 'Expiry alert days';
  static const maxDiscount = 'Max cashier discount (%)';
  static const receiptFooter = 'Receipt footer';
  static const pharmacyLogo = 'Pharmacy logo';
  static const uploadLogo = 'Upload logo';
  static const oldValue = 'Old value';
  static const newValue = 'New value';
  static const tableName = 'Table';
  static const actionLabel = 'Action';
  static const dateFrom = 'From';
  static const dateTo = 'To';

  // Dashboard
  static const todaySales = "Today's sales";
  static const monthSales = "This month's sales";
  static const grossProfitToday = 'Estimated gross profit today';
  static const invoiceCount = 'Invoices';
  static const openShifts = 'Open shifts';
  static const lowStock = 'Low stock';
  static const expiringSoon = 'Expiring soon';
  static const expired = 'Expired';
  static const last14Days = 'Last 14 days';
  static const topMedicines = 'Top medicines';
  static const alerts = 'Alerts';
  static const pendingPrescriptions = 'Pending prescriptions';
  static const shortcuts = 'Shortcuts';
  static const currentShift = 'Current shift';
  static const startShift = 'Start shift';
  static const mySalesToday = 'My sales today';
  static const noOpenShift = 'No open shift';
  static const purchaseOrdersToReceive = 'Orders waiting to be received';

  // Expenses
  static const expenseCategories = 'Rent, Salaries, Utilities, Transport, Supplies, Other';
  static const category = 'Category';
  static const paymentMethod = 'Payment method';
  static const receiptPhoto = 'Receipt photo';
  static const monthlyTotal = 'Monthly total';
  static const byCategory = 'By category';

  // Reports
  static const salesByDay = 'Sales summary by day';
  static const salesByCashier = 'Sales by cashier';
  static const salesByPaymentMethod = 'Sales by payment method';
  static const salesByMedicine = 'Sales by medicine';
  static const profitReport = 'Profit (revenue minus cost)';
  static const stockValuation = 'Stock valuation';
  static const expiryLosses = 'Expiry losses';
  static const purchasesBySupplier = 'Purchases by supplier';
  static const expensesReport = 'Expenses';
  static const netProfit = 'Net profit statement';
  static const shiftVariance = 'Shift cash variance';
  static const controlledRegister = 'Controlled / prescription-only register';
  static const period = 'Period';
  static const chart = 'Chart';
  static const allBranches = 'All branches';
  static const addBranch = 'Add branch';
  static const manageBranches = 'Manage branches';
  static const allBranchesViewOnly = 'All branches (view only)';
  static const chooseBranchFirst = 'Choose a branch in the top bar first.';
  static const activity = 'Activity log';
  static const recentActivity = 'Recent activity';
  static const timeRange = 'Time range';
  static const noActivity = 'No activity recorded for this period.';
  static const requestCorrection = 'Request correction';
  static const approveCorrection = 'Approve correction';
  static const pendingApproval = 'Pending approval';
  static const approved = 'Approved';
  static const dateTimeLabel = 'Date & time';
  static const auditNote = 'Actions are recorded with your email and time and cannot be edited or deleted without super admin approval.';

}
