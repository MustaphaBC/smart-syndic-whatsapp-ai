# Smart Syndic AI

Smart Syndic AI is a property-management prototype that connects residents to a WhatsApp support assistant and gives managers a Flutter dashboard for residences, residents, service tickets, broadcasts, and analytics.

## Architecture

- `main.py` — FastAPI service. It receives Twilio WhatsApp webhooks, verifies inbound requests, uses Groq models for text and image analysis, retrieves residence knowledge from ChromaDB, stores management data in PostgreSQL, and exposes REST and WebSocket APIs. Firebase Admin verifies app tokens and sends push notifications. Redis is optional; if it is unavailable, the current service runs without Redis-backed rate limiting.
- `ingest.py` — indexes local `data/*.json` knowledge documents into the ChromaDB collection `residence_rules` using a multilingual sentence-transformer embedding model.
- `Auto_Publisher.py` — optional workflow for creating rental-announcement images and publishing announcements through Facebook APIs or Playwright.
- `syndic_mobile/` — Flutter manager app with Firebase sign-in, residence selection, resident and ticket views, history, analytics, and push notifications.
- `Livrables/` — the project presentation and defense speech.

The public repository omits resident records, residence photos, the local vector database, generated announcement images, logs, browser sessions, and service credentials. Add your own approved data before running ingestion or announcement workflows.

## Requirements

- Python and the packages listed in `requirements.txt`.
- PostgreSQL for application data.
- Firebase project configuration for authentication and push notifications.
- A Groq API key and Twilio WhatsApp credentials for the assistant integration.
- Flutter SDK for the mobile app.
- Redis is optional; the backend falls back without Redis, but its Redis-backed rate limit is then disabled.

## Configure the backend

Create a virtual environment and install the Python dependencies from the repository root:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Copy `.env.example` to `.env` and fill in the values for your environment. The file contains only placeholders. Keep `.env`, Facebook cookies, and Firebase service-account credentials private.

The backend reads PostgreSQL settings from `DB_HOST`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD`. Provide a PostgreSQL server and database before starting the API. Set `GROQ_API_KEY`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_PHONE_NUMBER` to enable the WhatsApp and model integrations. Configure Firebase with either the `FIREBASE_CREDENTIALS` environment variable containing service-account JSON or a local `serviceAccountKey.json` file at the project root. The service-account file is ignored by Git.

Redis settings use `REDIS_HOST`, `REDIS_PORT`, and `REDIS_DB`. `ALLOWED_ORIGINS` controls browser origins for the API. Do not use wildcard CORS or development credentials in a public deployment.

## Add a knowledge base

The input corpus is intentionally not included. Place your own JSON documents in `data/`. Each file should contain a `documents` array; entries use `id`, `content`, `title`, `category`, and `urgency` fields. For example:

```json
{
  "source": "building_rules",
  "category_hint": "general",
  "documents": [
    {
      "id": "quiet-hours",
      "title": "Quiet hours",
      "content": "Describe the approved building policy here.",
      "category": "rules",
      "urgency": "P3"
    }
  ]
}
```

From the repository root, run:

```bash
python ingest.py
```

**Ingestion deletes and recreates the `residence_rules` collection.** Back up any local ChromaDB data you need before running it. The local `chroma_db/` directory and downloaded embedding model are not included in Git.

## Run the API

From the repository root:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

The health endpoint is `GET /health`; Twilio sends inbound WhatsApp messages to `POST /webhook`. Configure Twilio with a publicly reachable HTTPS URL ending in `/webhook`. The management API is under `/api/`, and the live update socket is `/ws`.

## Run the mobile app

Configure Firebase for your own Android/iOS app and enable the authentication and messaging products used by the client. Add the platform configuration locally; Firebase configuration files are ignored by Git.

```powershell
cd syndic_mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=https://your-api-host
```

`API_BASE_URL` is the base address of the FastAPI service. For a physical device, use a host address reachable from that device. Do not use the placeholder/default value in a real build.

## Optional Facebook announcements

`Auto_Publisher.py` reads unit details from `data/units.json`, looks for photos below `assets/<residence_id>/<unit_number>/`, and writes generated posters into `generated_announcements/`. Configure the Facebook credentials and group/page targets in your private `.env` before using it. Running this script can publish content to Facebook; review the target and generated announcement before enabling it.

## Privacy and deployment

This prototype processes resident messages, contact details, and optional photos. Depending on the enabled workflow, data may be sent to Twilio, Groq, Firebase, PostgreSQL, Redis, and Facebook. Use only data you are authorized to process, and replace every placeholder with credentials for services you control. The local databases, residence datasets, photos, cookie sessions, and secret files are not published here.

The backend should receive a deployment security review before public use. Configure HTTPS, trusted CORS origins, authentication and authorization for every administrative route, request limits, secret management, and production-safe error handling.
