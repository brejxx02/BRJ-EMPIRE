# BRJ EMPIRE — Premium Member Portal

A responsive member portal built with HTML/CSS/JavaScript and Supabase Auth + PostgreSQL with Row Level Security. No local-only login or fake transaction state is used.

## Included
- Member registration, email/password sign-in, session persistence and password reset
- Member dashboard and service package catalogue
- Payment request submission (UPI reference/UTR) and manual admin review
- Withdrawal request submission and manual review tracking
- Referral links and referral signup attribution
- Member activity log
- Main admin / sub-admin access enforced by database role and RLS/RPC
- Responsive premium dark interface

## Important operating model
This project records requests and review decisions. It does **not** itself collect a payment, verify a bank transfer, hold a wallet balance, transfer a payout, calculate investment returns, or pay referral commissions. Payment approval must be based on independent verification. A production payment gateway / payout provider requires its own server-side integration and webhook verification. Do not describe a request as paid or a payout as completed until the provider confirms it.

Packages in the starter schema are service catalogue entries. Do not use this code to promise fixed returns or pay existing members from new members' deposits. Have the actual business model, payment handling, referral compensation, tax and applicable Indian legal obligations reviewed by qualified professionals before accepting public funds.

## Setup

### 1. Create Supabase project
Create a project in Supabase. In **SQL Editor**, run the full `supabase-schema.sql` file.

### 2. Configure browser keys
Open `assets/config.js` and replace:
- `PASTE_SUPABASE_PROJECT_URL` with the project URL
- `PASTE_SUPABASE_PUBLISHABLE_OR_ANON_KEY` with the publishable/anon key
- `YOUR_BUSINESS_UPI_ID` with the verified business UPI ID
- `support@yourdomain.com` with your support address

Only the publishable/anon key belongs in browser code. Never use a service-role or secret key here.

### 3. Authentication settings
In Supabase Authentication settings:
- Set the Site URL to your deployed HTTPS URL.
- Add your deployed URL to allowed redirect URLs.
- Configure email confirmation and SMTP as required.
- Test registration, confirmation, login, logout and password reset.

### 4. Make the owner a main administrator
Register through the site. In Supabase **Authentication → Users**, find the account and copy its UUID. Run this in SQL Editor, replacing the placeholder with the verified UUID:

```sql
update public.profiles
set role = 'main_admin'
where id = 'OWNER_AUTH_USER_UUID';
```

Do not allow users to self-select an administrator role. Add sub-admins only after checking their identity:

```sql
update public.profiles
set role = 'sub_admin'
where id = 'VERIFIED_STAFF_AUTH_USER_UUID';
```

### 5. Change packages
Use the Supabase SQL editor or an authenticated main-admin database workflow to edit the catalogue. Example:

```sql
update public.packages
set name='Bronze', amount_inr=500, description='Your accurate service description'
where slug='bronze';
```

### 6. Deploy free on GitHub Pages
Upload `index.html`, the `assets/` folder and `supabase-schema.sql` to a GitHub repository. Enable **Settings → Pages → Deploy from a branch**, select the branch and root folder. The free address will be `https://YOUR-USERNAME.github.io/REPOSITORY/`. Use HTTPS and configure that exact URL in Supabase Auth.

## Before live launch
- Replace all configuration placeholders.
- Configure verified business payment instructions.
- Review RLS policies and test using two normal accounts, one sub-admin and one main-admin.
- Set up a privacy policy, terms, support channel and refund/cancellation policy.
- Do not store UPI PINs, OTPs, card PINs or CVVs.
- For automated payment verification and payouts, build a server-side integration with a compliant provider. Keep provider secrets on the server, verify webhook signatures, use idempotency, and maintain an auditable ledger.
- Have an Indian professional review the actual business model and applicable compliance requirements before taking money from customers.

## Files
- `index.html` — interface
- `assets/style.css` — responsive visual system
- `assets/app.js` — real Supabase-backed frontend
- `assets/config.js` — public configuration placeholders
- `supabase-schema.sql` — database tables, RLS, triggers and review RPC
