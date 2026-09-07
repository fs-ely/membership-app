# JasaSane Corp

A full-stack membership registration system with two-factor authentication (2FA). Users register with a phone number and password, log in via OTP verification, and gain the ability to register and manage member records. Any registered user can add members with their personal details, location, and profile image.

Built with:

- **Frontend**: React 18 (React Router v6, Axios), Create React App
- **Backend**: Express.js (Node.js)
- **Database**: PostgreSQL (`pg` pool)
- **Auth**: bcrypt (password hashing), jsonwebtoken (JWT), crypto (OTP generation)

## Features

### Authentication
- User registration with name, phone, and password
- Password-based login that generates a 6-digit OTP
- OTP delivered to the server console (simulated SMS; no SMS provider)
- Split 6-input OTP entry with auto-focus, backspace navigation, and paste support
- Single-use, expiring OTPs (5 minutes, configurable) validated against the database
- JWT-based authentication guarding protected routes
- Protected dashboard showing the authenticated user's profile with logout
- Forgot password flow that sends a reset OTP to the server console
- Persistent sessions via localStorage token + profile refresh

### Member Registration
- Register members with first name, last name, email address, and profile image
- Hierarchical location selection (Country → Province → City → Barangay)
- Edit and delete member records
- Role-based access: Admin sees all members, Regular users see only their own
- Profile image upload with preview

## How It Works

1. User registers with name, phone, and password (bcrypt-hashed).
2. User logs in with phone + password → the backend generates a 6-digit OTP, stores it in the `otps` table, and logs it to the server console.
3. User enters the OTP → the backend validates it (must be unused and unexpired), marks it used, and issues a JWT.
4. The JWT authorizes access to protected endpoints (e.g., `/profile`, `/records`), which the frontend uses to display the dashboard.
5. Any registered user can navigate to "Manage Records" and register new members by providing their first name, last name, email, location, and optional profile image.
6. Admin users can view and manage all member records; regular users can only view and manage their own records.

## Project Structure

```
membership-app/
├── backend/
│   ├── src/
│   │   ├── config/db.js              # PostgreSQL pool
│   │   ├── controllers/
│   │   │   ├── authController.js     # register/login/verifyOTP/getProfile/updateProfile
│   │   │   ├── recordController.js   # CRUD operations for member records
│   │   │   └── locationController.js # Country/province/city/barangay data
│   │   ├── middleware/
│   │   │   ├── auth.js               # JWT verification guard
│   │   │   └── role.js               # Role-based access control
│   │   ├── models/init.js            # Auto-creates users, otps, records tables
│   │   ├── routes/
│   │   │   ├── auth.js               # /api/auth routes
│   │   │   ├── records.js            # /api/records routes
│   │   │   └── locations.js          # /api/locations routes
│   │   ├── utils/
│   │   │   ├── otpGenerator.js       # Cryptographically secure 6-digit OTP
│   │   │   └── uploads.js            # File upload configuration
│   │   └── server.js                 # Express app entry point
│   ├── data/locations.json           # Philippine location data
│   ├── uploads/                      # Uploaded profile images
│   ├── .env                          # Environment configuration
│   └── package.json
└── frontend/
    └── src/
        ├── components/
        │   ├── LoginForm.jsx         # Phone + password login
        │   ├── RegisterForm.jsx      # User registration
        │   ├── OTPVerification.jsx   # 6-digit OTP entry
        │   ├── Dashboard.jsx         # User profile & navigation
        │   ├── RecordsList.jsx       # Member records table
        │   ├── RecordFormModal.jsx   # Create/edit member form
        │   ├── EditProfileModal.jsx  # Edit user profile
        │   ├── ForgotPassword.jsx    # Password reset flow
        │   ├── Modal.jsx             # Reusable modal component
        │   └── BrandHeader.jsx       # App header/branding
        ├── context/AuthContext.jsx   # Auth state + token persistence
        ├── services/api.js           # Axios client with auth interceptor
        ├── App.js                    # Routing + protected/public route guards
        └── index.js
```

## Prerequisites

- Node.js (v18+)
- PostgreSQL (v14+)

## Setup

### Step 0: Check Prerequisites

Make sure you have the following installed on your machine:

```bash
node --version    # Node.js v18 or newer
npm --version     # npm comes with Node.js
psql --version    # PostgreSQL v14 or newer
```

PostgreSQL must be installed and running locally on port `5432` before continuing.

### Step 1: Set Up the Database

Create the database (run once):

```bash
psql -U postgres -h localhost -c "CREATE DATABASE database_name;"
```

> Tables (`users`, `otps`, `records`) are created automatically when the backend server starts, so there is no need to run any migration scripts.

### Step 2: Configure the Backend Environment

The backend needs a `.env` file to know how to connect to the database and sign JWTs. Start by copying the provided template:

```bash
cd backend
cp .env.example .env
```

Now open `backend/.env` and update it to match your local setup:

| Variable             | Description                                              | Example                          |
| -------------------- | -------------------------------------------------------- | -------------------------------- |
| `PORT`               | Port the backend server runs on                          | `5000`                           |
| `DB_HOST`            | PostgreSQL host                                          | `localhost`                      |
| `DB_PORT`            | PostgreSQL port                                          | `5432`                           |
| `DB_NAME`            | Name of the database you created in Step 1               | `database_name`                  |
| `DB_USER`            | Your PostgreSQL username                                 | `postgres`                       |
| `DB_PASSWORD`        | Your PostgreSQL password                                 | `your_db_password`               |
| `JWT_SECRET`         | Secret used to sign authentication tokens (change this!) | `some_long_random_secret_string` |
| `OTP_EXPIRY_MINUTES` | How long a generated OTP remains valid (in minutes)      | `5`                              |

You **must** set `DB_USER` and `DB_PASSWORD` to the credentials of your local PostgreSQL, and change `JWT_SECRET` to your own secret string.

### Step 3: Install and Run the Backend

```bash
cd backend
npm install
npm run dev
```

`npm run dev` starts the backend with auto-reload (nodemon). It runs on `http://localhost:5000`.

> **Keep this terminal open.** The OTP is simulated — it is printed to this backend terminal's console (not sent via SMS), so you will need to read it from here when you log in.

Available backend commands:

| Command        | Description                           |
| -------------- | ------------------------------------- |
| `npm run dev`  | Development server with auto-reload   |
| `npm start`    | Run the backend normally (production) |
| `npm run seed` | Populate the database with demo users |

### Step 4: Install and Run the Frontend

Open a **second terminal** and run:

```bash
cd frontend
npm install
npm start
```

`npm start` runs the React app on `http://localhost:3000`. It proxies API calls to the backend at `http://localhost:5000` (configured via `proxy` in `package.json`).

### Step 5 (Optional): Seed Demo Data

To get started quickly with pre-created test users, run the seed script in the backend folder:

```bash
cd backend
npm run seed
```

This creates demo users (all with the password `Password@123`), so you can log in right away.

### Accessing the App

With both terminals running, open `http://localhost:3000` in your browser.

## Troubleshooting

| Problem                                       | Solution                                                                                                                                                    |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ECONNREFUSED` / PostgreSQL connection failed | Make sure PostgreSQL is installed and running on port `5432`, and that `DB_USER` / `DB_PASSWORD` in `backend/.env` match your local PostgreSQL credentials. |
| Port `3000` or `5000` already in use          | Either stop the process using that port, or change `PORT` in `backend/.env` and the `proxy` in `frontend/package.json`.                                     |
| No OTP received after login                   | The OTP is simulated and printed to the **backend terminal** console. Check the terminal running `npm run dev` (Step 3).                                    |
| Tables not created                            | Tables are created automatically when the backend starts. If they are missing, restart the backend.                                                         |

## Usage

1. Open `http://localhost:3000`
2. Register with a full name, phone number, and password
3. Login with phone + password
4. **Check the backend console** for the OTP (simulates SMS)
5. Enter the 6-digit OTP on the verification screen
6. Access the protected dashboard and log out when done

### Registering Members

1. Log in and navigate to the dashboard
2. Click **Manage Records**
3. Click **+ Add Record** to open the member registration form
4. Enter the member's first name, last name, email address, and optional profile image
5. Select the location using the cascading dropdowns (Country → Province → City → Barangay)
6. Click **Create** to save the member record
7. Edit or delete existing members using the **Edit** and **Delete** buttons in the records table

> Any registered user has the power to register new members. Admin users can view and manage all member records, while regular users can only manage the members they created.

## API Endpoints

### Authentication
| Method | Endpoint               | Description                               | Auth               |
| ------ | ---------------------- | ----------------------------------------- | ------------------ |
| GET    | `/api/health`          | Server health check                       | No                 |
| POST   | `/api/auth/register`   | Register new user (name, phone, password) | No                 |
| POST   | `/api/auth/login`      | Login, sends OTP to console               | No                 |
| POST   | `/api/auth/verify-otp` | Verify OTP, returns JWT for valid access  | No                 |
| POST   | `/api/auth/forgot-password` | Request password reset OTP (sent to console) | No           |
| POST   | `/api/auth/reset-password`  | Verify reset OTP and set new password    | No                 |
| GET    | `/api/auth/profile`    | Get authenticated user profile            | Yes (Bearer token) |
| PUT    | `/api/auth/profile`    | Update user profile (with image upload)   | Yes (Bearer token) |

### Member Records
| Method | Endpoint               | Description                               | Auth               |
| ------ | ---------------------- | ----------------------------------------- | ------------------ |
| GET    | `/api/records`         | Get all records (admin) or own records    | Yes (Bearer token) |
| GET    | `/api/records/:id`     | Get record by ID                          | Yes (Bearer token) |
| POST   | `/api/records`         | Create new member record                  | Yes (Bearer token) |
| PUT    | `/api/records/:id`     | Update member record                      | Yes (Bearer token) |
| DELETE | `/api/records/:id`     | Delete member record                      | Yes (Bearer token) |

### Locations (Philippine Address Data)
| Method | Endpoint               | Description                               | Auth               |
| ------ | ---------------------- | ----------------------------------------- | ------------------ |
| GET    | `/api/locations/countries` | Get list of countries                 | No                 |
| GET    | `/api/locations/provinces/:countryId` | Get provinces by country     | No                 |
| GET    | `/api/locations/cities/:provinceId` | Get cities by province         | No                 |
| GET    | `/api/locations/barangays/:cityId` | Get barangays by city           | No                 |

## Configuration (.env)

```
PORT=5000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=database_name
DB_USER=postgres
DB_PASSWORD=your_password
JWT_SECRET=your_secret_key
OTP_EXPIRY_MINUTES=5
```

## Notes

- OTP is logged to the server console (an SMS provider integration can replace this)
- JWT expires in 1 hour
- OTPs are single-use and expire after 5 minutes
- Passwords are hashed with bcrypt (10 salt rounds)
- For production, use environment variables for secrets and add rate limiting
