# OTP/2FA Authentication App

A full-stack authentication demo implementing two-factor authentication (2FA) using a one-time password (OTP). A user registers with a phone number and password, logs in, and receives a 6-digit OTP that must be verified before a JWT is issued for access to protected routes.

Built with:
- **Frontend**: React 18 (React Router v6, Axios), Create React App
- **Backend**: Express.js (Node.js)
- **Database**: PostgreSQL (`pg` pool)
- **Auth**: bcrypt (password hashing), jsonwebtoken (JWT), crypto (OTP generation)

## Features
- User registration with name, phone, and password
- Password-based login that generates a 6-digit OTP
- OTP delivered to the server console (simulated SMS; no SMS provider)
- Split 6-input OTP entry with auto-focus, backspace navigation, and paste support
- Single-use, expiring OTPs (5 minutes, configurable) validated against the database
- JWT-based authentication guarding protected routes
- Protected dashboard showing the authenticated user's profile with logout
- Persistent sessions via localStorage token + profile refresh

## How It Works
1. User registers with name, phone, and password (bcrypt-hashed).
2. User logs in with phone + password → the backend generates a 6-digit OTP, stores it in the `otps` table, and logs it to the server console.
3. User enters the OTP → the backend validates it (must be unused and unexpired), marks it used, and issues a JWT.
4. The JWT authorizes access to protected endpoints (e.g., `/profile`), which the frontend uses to display the dashboard.

## Project Structure
```
opencode-activity/
├── backend/
│   ├── src/
│   │   ├── config/db.js            # PostgreSQL pool
│   │   ├── controllers/authController.js  # register/login/verifyOTP/getProfile
│   │   ├── middleware/auth.js      # JWT verification guard
│   │   ├── models/init.js          # Auto-creates users & otps tables
│   │   ├── routes/auth.js          # /api/auth routes
│   │   ├── server.js               # Express app entry point
│   │   └── utils/otpGenerator.js   # Cryptographically secure 6-digit OTP
│   ├── .env                        # Environment configuration
│   └── package.json
└── frontend/
    └── src/
        ├── components/             # LoginForm, RegisterForm, OTPVerification, Dashboard
        ├── context/AuthContext.jsx # Auth state + token persistence
        ├── services/api.js         # Axios client with auth interceptor
        ├── App.js                  # Routing + protected/public route guards
        └── index.js
```

## Prerequisites
- Node.js (v18+)
- PostgreSQL (v14+)

## Setup

### 1. Database
```bash
# Create database
psql -U postgres -h localhost -c "CREATE DATABASE otp_auth_db;"
```

Tables are auto-created on server startup.

### 2. Backend
```bash
cd backend
npm install

# Edit .env to match your PostgreSQL credentials
# DB_USER, DB_PASSWORD, JWT_SECRET

npm start        # production
npm run dev      # development (auto-reload with nodemon)
```

### 3. Frontend
```bash
cd frontend
npm install
npm start
```

The frontend runs on `http://localhost:3000` and proxies API calls to the backend at `http://localhost:5000` (configured via `proxy` in `package.json`).

## Usage
1. Open `http://localhost:3000`
2. Register with a full name, phone number, and password
3. Login with phone + password
4. **Check the backend console** for the OTP (simulates SMS)
5. Enter the 6-digit OTP on the verification screen
6. Access the protected dashboard and log out when done

## API Endpoints
| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/health` | Server health check | No |
| POST | `/api/auth/register` | Register new user (name, phone, password) | No |
| POST | `/api/auth/login` | Login, sends OTP to console | No |
| POST | `/api/auth/verify-otp` | Verify OTP, returns JWT for valid access | No |
| GET | `/api/auth/profile` | Get authenticated user profile | Yes (Bearer token) |

## Configuration (.env)
```
PORT=5000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=otp_auth_db
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
