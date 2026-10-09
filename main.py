import asyncio
import os
import re
import json
import time
import uuid
import hashlib
import unicodedata
import asyncpg
import uvicorn
import httpx
from contextlib import asynccontextmanager
from fastapi import FastAPI, Response, HTTPException, Request, WebSocket, WebSocketDisconnect, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field, field_validator
from groq import Groq
import chromadb
from chromadb.utils import embedding_functions
from dotenv import load_dotenv
from twilio.rest import Client
from twilio.twiml.messaging_response import MessagingResponse
from twilio.request_validator import RequestValidator
from pydub import AudioSegment
import speech_recognition as sr
import base64
from langdetect import detect, LangDetectException
import firebase_admin
from firebase_admin import messaging
from firebase_admin import credentials, auth as firebase_auth
import logging
from groq import AsyncGroq
async_groq_client = AsyncGroq(api_key=os.getenv("GROQ_API_KEY"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("syndic_api")

# ══════════════════════════════════════════════════════════════════════════════
# 1. CONFIGURATION GLOBALE
# ══════════════════════════════════════════════════════════════════════════════
load_dotenv()
os.environ["ANONYMIZED_TELEMETRY"] = "False"

# ── Redis (rate limiting) ─────────────────────────────────────────────────────
try:
    import redis as redis_lib
    _redis_client = redis_lib.Redis(
        host=os.getenv("REDIS_HOST", "localhost"),
        port=int(os.getenv("REDIS_PORT", 6379)),
        db=int(os.getenv("REDIS_DB", 0)),
        decode_responses=True,
        socket_connect_timeout=2,
    )
    _redis_client.ping()
    logger.info(f"✅ Redis connecté — rate limiting activé.")
except Exception as _re:
    _redis_client = None
    logger.warning(f"⚠️ Redis indisponible ({_re}) — rate limiting désactivé (dégradé gracieux).")

# ── Constantes ────────────────────────────────────────────────────────────────
LANG_TO_LOCALE = {"fr": "fr-FR", "ar": "ar-MA", "ar_darija": "ar-MA", "en": "en-US", "es": "es-ES"}
SLA_MAP = {"P0": 5, "P1": 30, "P2": 240, "P3": 1440}
SLA_LABEL = {"P0": "5 minutes", "P1": "30 minutes", "P2": "4 heures", "P3": "24 heures"}
ASSIGNEE_MAP = {
    "FUITE_GAZ":          "Urgence Gaz",
    "INCENDIE":           "Protection Civile",
    "ASCENSEUR_URGENCE":  "Technicien Ascenseur",
    "INONDATION_MAJEURE": "Plombier",
    "SÉCURITÉ":           "Gardien + Police",
    "Plomberie":          "Plombier",
    "Electricité":        "Électricien",
    "Ascenseur":          "Technicien Ascenseur",
    "Nuisances":          "Gardien",
    "Parking":            "Gardien",
    "Propreté":           "Service Nettoyage",
}

# Modèle LLM principal
LLM_MODEL = "llama-3.3-70b-versatile"

# Modèle Vision 
VISION_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"

# ── Init Firebase Sécurisé ─────────────────────────────────────────────────────
if not firebase_admin._apps:
    try:
        firebase_env = os.getenv("FIREBASE_CREDENTIALS")
        
        if firebase_env:
            cred_dict = json.loads(firebase_env)
            cred = credentials.Certificate(cred_dict)
            logger.info("✅ Firebase initialisé via Variable d'Environnement (Sécurisé)")
        else:
            cred = credentials.Certificate("serviceAccountKey.json")
            logger.warning("⚠️ Firebase initialisé via fichier JSON (Mode Local)")
            
        firebase_admin.initialize_app(cred)
    except Exception as e:
        logger.error(f"❌ Erreur initialisation Firebase: {e}")

security = HTTPBearer()
# ── Clients API ───────────────────────────────────────────────────────────────
groq_client   = None
twilio_client = None
twilio_number = None

try:
    groq_client   = Groq(api_key=os.getenv("GROQ_API_KEY"))
    twilio_client = Client(os.getenv("TWILIO_ACCOUNT_SID"), os.getenv("TWILIO_AUTH_TOKEN"))
    twilio_number = os.getenv("TWILIO_PHONE_NUMBER")
    logger.info("✅ APIs Groq + Twilio configurées.")
except Exception as e:
    logger.warning(f"⚠️ Erreur Config API: {e}")

# ── ChromaDB ──────────────────────────────────────────────────────────────────
collection = None
try:
    chroma_client  = chromadb.PersistentClient(path="./chroma_db")
    embedding_func = embedding_functions.SentenceTransformerEmbeddingFunction(
        model_name="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
    )
    collection = chroma_client.get_or_create_collection(
        name="residence_rules", embedding_function=embedding_func
    )
    logger.info(f"✅ ChromaDB connecté — {collection.count()} chunks.")
except Exception as e:
    logger.error(f"❌ Erreur ChromaDB: {e}")

# ── Rate limiting IP ────────────────────────────────────────────────────────────────────
def check_ip_rate_limit(ip: str, max_attempts: int = 5, window_seconds: int = 3600) -> bool:
    if _redis_client is None:
        return True
    ip_hash = hashlib.sha256(ip.encode("utf-8")).hexdigest()
    key     = f"invite_rl:{ip_hash}"
    now     = int(time.time())
    try:
        pipe = _redis_client.pipeline()
        pipe.zremrangebyscore(key, 0, now - window_seconds)
        pipe.zcard(key)
        pipe.zadd(key, {str(now) + "_" + uuid.uuid4().hex[:4]: now})
        pipe.expire(key, window_seconds + 5)
        results = pipe.execute()
        if results[1] >= max_attempts:
            return False
        return True
    except Exception:
        return True
    
# ══════════════════════════════════════════════════════════════════════════════
# 2. POOL POSTGRESQL
# ══════════════════════════════════════════════════════════════════════════════
@asynccontextmanager
async def lifespan(app_: FastAPI):
    global db_pool
    try:
        db_pool = await asyncpg.create_pool(
            host=os.getenv("DB_HOST", "localhost"),
            database=os.getenv("DB_NAME", "pfe_db"),
            user=os.getenv("DB_USER", "postgres"),
            password=os.getenv("DB_PASSWORD"),
            min_size=5,
            max_size=20,
            command_timeout=30,
        )
        logger.info("✅ Pool PostgreSQL créé (asyncpg, 5–20 connexions).")
        await init_db()
    except Exception as e:
        logger.error(f"❌ Erreur création pool DB: {e}")
    yield

    if db_pool:
        await db_pool.close()
        logger.info("✅ Pool PostgreSQL fermé.")

app = FastAPI(title="Syndic IA", lifespan=lifespan)

from fastapi.middleware.cors import CORSMiddleware
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

@app.get("/health")
async def health_check():
    db_status = "ok" if db_pool else "disconnected"
    return {
        "status": "ok",
        "database": db_status,
        "environment": "production"
    }
# ══════════════════════════════════════════════════════════════════════════════
# 3. MODÈLES PYDANTIC
# ══════════════════════════════════════════════════════════════════════════════
class ValidationRequest(BaseModel):
    ticket_id: int
    text:      str = Field(..., min_length=1, max_length=5000)
    phone:     str = Field(..., min_length=5, max_length=50)

class ResidentModel(BaseModel):
    unit:         str = Field(..., min_length=1, max_length=20)
    name:         str = Field(..., min_length=2, max_length=100)
    phone:        str = Field(..., min_length=8, max_length=20)
    residence_id: str = Field(..., min_length=3, max_length=50)

    @field_validator("phone")
    @classmethod
    def phone_format(cls, v: str) -> str:
        clean = v.strip().replace(" ", "")
        if not (clean.startswith("+") or clean.startswith("0")):
            raise ValueError("Numéro invalide — doit commencer par + ou 0")
        return clean

class UpdateResidentModel(BaseModel):
    old_unit:     str = Field(..., min_length=1, max_length=20)
    new_unit:     str = Field(..., min_length=1, max_length=20)
    new_name:     str = Field(..., min_length=2, max_length=100)
    new_phone:    str = Field(..., min_length=8, max_length=20)
    residence_id: str = Field(..., min_length=3, max_length=50)

class ResidenceModel(BaseModel):
    name:        str = Field(..., min_length=2, max_length=100)
    city:        str = Field("",  max_length=100)
    address:     str = Field("",  max_length=200)
    units_count: int = Field(0,   ge=0, le=9999)

class BroadcastRequest(BaseModel):
    message:      str = Field(..., min_length=5, max_length=1600)  # Limite SMS WhatsApp
    residence_id: str = Field(..., min_length=3, max_length=50)

class RuleRequest(BaseModel):
    rule: str = Field(..., min_length=10, max_length=500)

class InviteCodeRequest(BaseModel):
    code: str = Field(..., min_length=4, max_length=20)

class UseInviteCodeRequest(BaseModel):
    code:  str = Field(..., min_length=4,  max_length=20)
    email: str = Field(..., min_length=5,  max_length=100)

    @field_validator("email")
    @classmethod
    def email_format(cls, v: str) -> str:
        if "@" not in v or "." not in v.split("@")[-1]:
            raise ValueError("Format email invalide")
        return v.lower().strip()

# ══════════════════════════════════════════════════════════════════════════════
# 3. AUTHENTIFICATION
# ══════════════════════════════════════════════════════════════════════════════
def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    try:
        return firebase_auth.verify_id_token(creds.credentials)
    except firebase_auth.ExpiredIdTokenError:
        raise HTTPException(status_code=401, detail="Token expiré")
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Non autorisé: {e}")

# ══════════════════════════════════════════════════════════════════════════════
# 4. PIPELINE — Anonymisation, Déduplication, Nettoyage, Routage
# ══════════════════════════════════════════════════════════════════════════════
def hash_phone(phone_raw: str) -> str:
    clean = phone_raw.replace("whatsapp:", "").strip()
    return hashlib.sha256(clean.encode("utf-8")).hexdigest()

def build_content_hash(phone_raw: str, text: str) -> str:
    phone_clean = phone_raw.replace("whatsapp:", "").strip()
    text_norm   = " ".join(text.lower().strip().split())
    return hashlib.sha256(f"{phone_clean}|{text_norm}".encode("utf-8")).hexdigest()

async def is_duplicate(content_hash: str, window_minutes: int = 5) -> bool:
    if not db_pool:
        return False
    try:
        async with db_pool.acquire() as conn:
            row = await conn.fetchrow(
                """SELECT id FROM tickets
                   WHERE content_hash = $1
                     AND datetime >= NOW() - ($2::integer * INTERVAL '1 minute')
                   LIMIT 1""",
                content_hash, window_minutes
            )
            return row is not None
    except Exception as e:
        logger.warning(f"⚠️ Erreur check doublon: {e}")
        return False

def clean_text(text: str) -> str:
    if not text:
        return ""
    text = "".join(c for c in text if unicodedata.category(c)[0] != "C" or c == "\n")
    text = " ".join(text.split())
    return text.strip()

def determine_assignee(category: str, urgency: str) -> str:
    if urgency in ("P0", "P1"):
        return ASSIGNEE_MAP.get(category, "Technicien" if urgency == "P1" else "Syndic + Secours")
    return ASSIGNEE_MAP.get(category, "Syndic")

def verify_twilio_signature(request: Request, form_dict: dict) -> bool:
    try:
        validator = RequestValidator(os.getenv("TWILIO_AUTH_TOKEN"))
        signature = request.headers.get("X-Twilio-Signature", "")
        return validator.validate(str(request.url), form_dict, signature)
    except Exception as e:
        logger.warning(f"⚠️ Erreur validation Twilio: {e}")
        return False

# ══════════════════════════════════════════════════════════════════════════════
# 5. DÉTECTION DE LANGUE
# ══════════════════════════════════════════════════════════════════════════════
_DARIJA_TOKENS = {
    "wach", "kayen", "kayan", "fin", "kifach", "3lach", "daba", "bghit",
    "khoya", "lah", "walakin", "mashi", "smiyti", "ana", "nta", "hna",
    "zwine", "kbir", "sghir", "dyali", "dyalna", "matalan", "mzyan",
    "allah", "inshallah", "merci", "chokran", "3afak", "afak", "aji",
    "ghadi", "bghina", "wqila", "mazal", "hakda", "mhbous", "l7al",
    "fiha", "fih", "dial", "nhar", "lila", "7aja", "chi7aja",
    "dyal", "ri7a", "rih", "kayn", "moshkil", "darna", "lma", "lgarage", 
    "bab", "ma", "kayt7ellch", "7abssna", "moshkil", "sda3", "jaran",  
    "khatira", "lhall", "chno", "khassni", "ndir", "skan", "mn", "sbah",  
}

# Indicateurs de langue dans le texte
_AR_SCRIPT_RE = re.compile(r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]")
def detect_language(text: str) -> str:
    if not text or len(text.strip()) < 3:
        return "fr"

    text_stripped = text.strip()

    # ── Couche 1 : Détection script arabe ────────────────────────────────────
    arabic_chars = len(_AR_SCRIPT_RE.findall(text_stripped))
    total_alpha  = sum(1 for c in text_stripped if c.isalpha())
    arabic_ratio = arabic_chars / total_alpha if total_alpha > 0 else 0

    # ── Couche 2 : Détection Darija romanisée ────────────────────────────────
    tokens      = set(re.findall(r"[a-zA-Z0-9'3]+", text_stripped.lower()))
    darija_hits = tokens & _DARIJA_TOKENS
    darija_score = len(darija_hits)
    darija_ratio = len(darija_hits) / len(tokens) if tokens else 0
    is_darija_romanise = darija_score >= 2 or darija_ratio > 0.15

    # Signal fort Darija même avec 1 seul token (mots très spécifiques)
    STRONG_DARIJA = {"ri7a", "moshkil", "kayt7ellch", "7abssna", "khassni",
                     "ndir", "skan", "lgarage", "lhall", "khatira"}
    if darija_score == 1 and darija_hits & STRONG_DARIJA:
        is_darija_romanise = True

    # ── Décision combinée ────────────────────────────────────────────────────
    if arabic_ratio > 0.35 and not is_darija_romanise:
        logger.info(f"🌐 Arabe script ({arabic_chars}/{total_alpha} chars)")
        return "ar"

    if is_darija_romanise:
        logger.info(f"🌐 Darija romanisé détecté: {darija_hits}")
        return "ar_darija"

    if arabic_ratio > 0.15:
        return "ar"

    # ── Couche 3 : langdetect ─────────────────────────────────────────────────
    if len(text_stripped) >= 8:
        try:
            lang = detect(text_stripped)
            if lang in ("ar", "fa", "ur"):
                return "ar"
            if lang in ("fr", "en", "es"):
                return lang
            if lang in ("ca", "pt", "it", "ro"):
                return "fr"
        except LangDetectException:
            pass

    return "fr"

def get_lang_instruction(lang: str, urgency: str = "P3") -> str:
    tone_by_urgency = {
        "P0": "Sois TRÈS BREF (1-2 phrases max), direct, rassurant. "
              "Confirme que les secours/techniciens sont alertés.",
        "P1": "Sois bref (2-3 phrases), professionnel. "
              "Confirme la prise en charge et donne un délai.",
        "P2": "Sois poli et précis (3-4 phrases). "
              "Explique la procédure et le délai de traitement.",
        "P3": "Sois chaleureux, détaillé et utile (3-5 phrases). "
              "Réponds complètement à la question ou demande.",
    }
    tone = tone_by_urgency.get(urgency, tone_by_urgency["P3"])

    instructions = {
        "ar_darija": (
            "IMPORTANT : Le résident écrit en Darija marocain romanisé (alphabet latin). "
            "Tu DOIS répondre en Darija romanisé — PAS en arabe standard, PAS en français. "
            "Exemples de formules Darija : 'Salam', 'Wakha', 'Inshallah', 'Barak Allah fik', "
            "'Mzyan', 'Mashi moshkil', 'Ghadi nsifto', 'F 30 dqiqa'. "
            "Utilise le même registre que le résident. Si le résident mélange français et Darija, "
            "tu peux aussi mélanger. "
            f"{tone}"
        ),
        # ── Arabe standard / script arabe ────────────────────────────────────
        "ar": (
            "الرجاء الرد باللغة العربية المغربية (الدارجة) إذا كانت الرسالة بالدارجة، "
            "أو بالعربية الفصحى إذا كانت الرسالة بالفصحى. "
            "استخدم عبارات المجاملة المغربية (السلام عليكم، بارك الله فيك، إن شاء الله...). "
            f"{tone}"
        ),
        "en": (
            "Respond ONLY in English. Use polite and professional language. "
            f"{tone}"
        ),
        "fr": (
            "Réponds UNIQUEMENT en français. "
            "Utilise des formules de politesse françaises (Bonjour, Cordialement...). "
            f"{tone}"
        ),
    }
    return instructions.get(lang, instructions["fr"])

# ══════════════════════════════════════════════════════════════════════════════
# 6. GARDES-FOUS SÉCURITÉ 
# ══════════════════════════════════════════════════════════════════════════════
def check_safety_keywords(text: str):
    if not text:
        return None, None
    t = text.lower().strip()

    # ── Négations — neutralise les faux positifs ──────────────────────────────
    negations = [
        "pas de feu", "aucun feu", "ni feu", "pas d'incendie",
        "pas de fumée", "pas de gaz", "pas de fuite",
        "situation semble maîtrisée", "pas d'urgence",
        "ma kaynch", "machi had", "barakallah",  
    ]
    for neg in negations:
        t = t.replace(neg, "___")

    # ── FUITE DE GAZ ──────────────────────────────────────────────────────────
    GAS_FR = ["fuite de gaz", "odeur de gaz", "gaz qui fuit", "robinet gaz",
              "arrivée de gaz", "sentir gaz", "ça sent le gaz"]
    GAS_AR = ["تسرب غاز", "رائحة غاز", "غاز", "ريحة الكاز", "ريحة gaz",
              "ريحة dial gaz", "kazen dial gaz", "rih dial gaz", "chi rih", 
              "rih bizarre", "odeur bizarre gaz", "hadi khatira", 
              "ri7a dyal gaz", "ri7a dial gaz", "ri7a d gaz", "ri7a gaz",           
              "rih dyal gaz", "rih dial gaz", "kayn ri7a", "kayna ri7a",                                       
              ]
    
    if (any(k in t for k in GAS_FR)
        or any(k in t for k in GAS_AR)
        or ("odeur" in t and any(x in t for x in ["bizarre", "gaz", "fort"]))
        or ("gaz" in t and any(x in t for x in ["fuite", "odeur", "danger", "évacuer", "kayn"]))
        # Détection Darija : ri7a + contexte gaz dans la même phrase
        or ("ri7a" in t and any(x in t for x in ["gaz", "khatira", "danger", "خطيرة"]))
        or ("rih" in t and "gaz" in t)):
        return "P0", "FUITE_GAZ"

    # ── INCENDIE ──────────────────────────────────────────────────────────────
    FIRE_FR = ["feu", "incendie", "flamme", "fumée", "brûlé", "brule", "fume",
               "ça brûle", "il y a le feu"]
    FIRE_AR = ["حريق", "نار", "دخان", "يحترق", "l7riq", "nar", "dkhan",
               "kahrik", "hriqa", "kayen l7riq", "wahed l7riq"]
    if any(k in t for k in FIRE_FR) or any(k in t for k in FIRE_AR):
        return "P0", "INCENDIE"

    # ── ASCENSEUR BLOQUÉ ──────────────────────────────────────────────────────
    LIFT_FR = ["ascenseur", "ascenceur"]
    LIFT_BLOCKED = ["bloqué", "coincé", "coincé", "panne", "dedans",
                    "mhbous", "mhbouss", "7bous", "dakhel", "dakhl"]
    if any(k in t for k in LIFT_FR) and any(x in t for x in LIFT_BLOCKED):
        return "P0", "ASCENSEUR_URGENCE"
    # Darija pur
    if any(x in t for x in ["l7mam mhbous", "mhbous f", "bloqué f l"]):
        return "P0", "ASCENSEUR_URGENCE"

    # ── SÉCURITÉ ──────────────────────────────────────────────────────────────
    SEC_FR = ["agression", "bagarre", "voleur", "sang", "cambriolage",
              "cambrioleur", "intrusion", "viol", "attaque", "menace"]
    SEC_AR = ["ضرب", "سرقة", "لص", "عدوان", "خطر", "نجدة",
              "darb", "serqa", "3udwan", "l7al khatir", "3awni", "3awnini"]
    if any(k in t for k in SEC_FR) or any(k in t for k in SEC_AR):
        return "P0", "SÉCURITÉ"

    # ── INONDATION MAJEURE ────────────────────────────────────────────────────
    FLOOD_FR = ["inondation", "noyé", "eau partout", "cave inondée",
                "ça coule partout", "eau au plafond"]
    FLOOD_AR = ["فيضان", "الماء فيضان", "lma f kol blasa", "lma ghata",
                "lma msha f bito", "lma nazl"]
    if any(k in t for k in FLOOD_FR) or any(k in t for k in FLOOD_AR):
        return "P0", "INONDATION_MAJEURE"

    return None, None

# ══════════════════════════════════════════════════════════════════════════════
# 7. RAG — 
# ══════════════════════════════════════════════════════════════════════════════
def get_rag_context(query: str, category_hint: str = None, n_results: int = 5) -> str:
    if not collection or collection.count() == 0:
        return ""

    # ── Query expansion ───────────────────────────────────────────────────────
    category_expansions = {
        "FUITE_GAZ":          "fuite gaz odeur danger évacuation robinet",
        "INCENDIE":           "incendie feu flammes fumée extinction alarme",
        "ASCENSEUR_URGENCE":  "ascenseur bloqué panne personne coincée",
        "Plomberie":          "fuite eau plombier canalisation robinetterie",
        "Electricité":        "panne électricité disjoncteur tableau électrique",
        "Ascenseur":          "ascenseur maintenance panne service technicien",
        "Nuisances":          "bruit tapage voisin nuisance nocturne",
        "Administratif":      "document attestation quittance certificat syndic",
        "Parking":            "parking stationnement place véhicule",
        "Propreté":           "nettoyage ordures déchets propreté parties communes",
    }

    expanded_query = query
    if category_hint and category_hint in category_expansions:
        expanded_query = f"{query} {category_expansions[category_hint]}"

    try:
        if category_hint:
            cat_lower = category_hint.lower().replace("é", "e").replace("è", "e")
            chroma_cat_map = {
                "fuite_gaz": "securite",    "incendie":  "securite",
                "sécurité":  "securite",    "sécurité":  "securite",
                "plomberie": "plomberie",   "electricite": "electricite",
                "electricité": "electricite", "ascenseur_urgence": "ascenseur",
                "ascenseur": "ascenseur",   "nuisances": "nuisances",
                "administratif": "administratif", "contacts": "contacts", "faq": "administratif",
            }
            chroma_cat = chroma_cat_map.get(cat_lower)
            if chroma_cat:
                rag_res = collection.query(
                    query_texts=[expanded_query],
                    n_results=n_results,
                    where={"category": chroma_cat},
                )
                if not rag_res["documents"] or not rag_res["documents"][0]:
                    rag_res = collection.query(
                        query_texts=[expanded_query], n_results=n_results)
            else:
                rag_res = collection.query(
                    query_texts=[expanded_query], n_results=n_results)
        else:
            rag_res = collection.query(
                query_texts=[expanded_query], n_results=n_results)

        if not rag_res["documents"] or not rag_res["documents"][0]:
            return ""

        # ── Filtrage par distance cosinus ─────────────────────────────────────
        docs      = rag_res["documents"][0]
        distances = rag_res.get("distances", [[]])[0]

        if distances:
            RAG_DISTANCE_THRESHOLD = float(os.getenv("RAG_DISTANCE_THRESHOLD", "0.75"))

            filtered = [
                doc for doc, dist in zip(docs, distances)
                if dist < RAG_DISTANCE_THRESHOLD
            ]
        else:
            filtered = docs

        if not filtered:
            filtered = docs[:2] 

        # ── Déduplication par similarité textuelle simple ─────────────────────
        unique_docs = []
        for doc in filtered:
            sig = doc[:80].strip()
            if not any(sig in ud for ud in unique_docs):
                unique_docs.append(doc)

        context = "\n---\n".join(unique_docs[:4])
        logger.info(f"📚 RAG: {len(unique_docs)} chunks pertinents récupérés")
        return context

    except Exception as e:
        logger.warning(f"⚠️ RAG indisponible: {e}")
        return ""

# ══════════════════════════════════════════════════════════════════════════════
# 8. HISTORIQUE RÉSIDENT 
# ══════════════════════════════════════════════════════════════════════════════
async def get_resident_history(phone_raw: str, limit: int = 3) -> list:
    phone_hash = hash_phone(phone_raw)
    if not db_pool:
        return []
    try:
        async with db_pool.acquire() as conn:
            rows = await conn.fetch(
                """SELECT text, urgency_level, category, status, datetime
                   FROM tickets WHERE phone_number = $1
                   ORDER BY datetime DESC LIMIT $2""",
                phone_hash, limit
            )
            return [
                {
                    "text":     (r["text"] or "")[:100],
                    "urgency":  r["urgency_level"] or "P3",
                    "category": r["category"] or "Autre",
                    "status":   r["status"] or "pending",
                    "date":     r["datetime"].strftime("%d/%m %H:%M") if r["datetime"] else "",
                }
                for r in rows
            ]
    except Exception as e:
        logger.warning(f"⚠️ Erreur historique résident: {e}")
        return []

def detect_escalation(current_text: str, history: list) -> bool:
    if not history:
        return False
    escalation_markers = [
        "encore", "toujours", "pas encore", "rien n'a changé", "toujours pas",
        "je relance", "j'ai déjà signalé", "depuis", "ça fait",
        "mazal", "mazal hna", "walo", "3awad", "mhall chi",  # darija
        "لم يتم", "لازال", "ما زال",  # arabe
    ]
    t_lower = current_text.lower()
    if any(marker in t_lower for marker in escalation_markers):
        return True
    if history and history[0]["status"] == "pending":
        return True
    return False

def format_history_for_prompt(history: list, is_escalation: bool) -> str:
    if not history:
        return ""
    lines = ["📋 HISTORIQUE RÉCENT DU RÉSIDENT :"]
    for h in history:
        status_icon = "✅" if h["status"] == "validated" else "⏳"
        lines.append(
            f"  {status_icon} [{h['date']}] {h['urgency']} - {h['category']}: "
            f"'{h['text'][:60]}...' → {h['status']}"
        )
    if is_escalation:
        lines.append("⚠️ ESCALADE DÉTECTÉE : Le résident relance un problème non résolu.")
    return "\n".join(lines)

# ══════════════════════════════════════════════════════════════════════════════
# 9. LLM 
# ══════════════════════════════════════════════════════════════════════════════
def build_system_prompt(
    res_id: str,
    name: str,
    unit: str,
    lang: str,
    urgency_hint: str,
    rag_context: str,
    history_context: str,
    safety_instruction: str,
) -> str:
    lang_instr = get_lang_instruction(lang, urgency_hint or "P3")
    greeting_examples = {
        "fr":       f"Bonjour {name},",
        "ar":       f"السلام عليكم {name}،",
        "ar_darija":f"Salam {name},",   
        "en":       f"Hello {name},",
    }.get(lang, f"Bonjour {name},")

    rag_section = f"""
📚 RÈGLEMENT DE LA RÉSIDENCE (extraits pertinents) :
{rag_context}
""" if rag_context else ""
    history_section = f"\n{history_context}\n" if history_context else ""
    if rag_context:
        rag_fallback = ""
    else:
        rag_fallback = """
⚠️ CONTEXTE RAG : Aucune règle spécifique trouvée.
→ Ne renvoie PAS le résident vers "le règlement" sans plus d'info.
→ Réponds avec le bon sens des règles de copropriété.
→ Si tu ne peux pas répondre précisément, oriente vers le syndic :
   WhatsApp 7j/7, bureau lun-ven 9h-17h.
"""

    return f"""Tu es l'assistant IA du syndic de la résidence {res_id}.
Tu réponds au nom du syndic professionnel.
Résident : {name} (Appartement {unit}).

{lang_instr}

═══════════════════════════════════════════════
⛔ RÈGLES ABSOLUES — NE JAMAIS ENFREINDRE :
1. L'identité est DÉJÀ VÉRIFIÉE. NE JAMAIS demander de confirmer le nom ou l'appartement.
   Tu sais que tu parles à {name}, Appartement {unit}. Traite la demande directement.
2. NE JAMAIS inventer des informations (codes wifi, prix, numéros...) non présentes dans le contexte.
3. NE JAMAIS terminer par une question inutile si la réponse est complète.
═══════════════════════════════════════════════

Commence ta réponse par : "{greeting_examples}"
{rag_section}
{rag_fallback}
{history_section}
{safety_instruction}

═══════════════════════════════════════════════
CLASSIFICATION DES URGENCES :
• P0 — Urgence Vitale (SLA: 5 min)  : Incendie, gaz, agression, personne bloquée
• P1 — Dégâts Majeurs (SLA: 30 min) : Fuite eau importante, panne électrique bâtiment
• P2 — Gêne Significative (SLA: 4h) : Bruit, parking bloqué, badge perdu
• P3 — Information/Admin (SLA: 24h) : Question règlement, document, demande simple

CATÉGORIES DISPONIBLES :
Plomberie | Electricité | Ascenseur | Sécurité | Nuisances | Parking | Propreté | Administratif | Autre

SENTIMENT :
Frustré | Stressé | Neutre | Satisfait | Positif

═══════════════════════════════════════════════
RETOURNE UNIQUEMENT CE JSON (sans markdown, sans texte avant/après) :
{{
  "response":       "Réponse complète au résident...",
  "category":       "UneCategorie",
  "urgency_level":  "P0|P1|P2|P3",
  "sentiment":      "Frustré|Stressé|Neutre|Satisfait|Positif",
  "sub_category":   "Précision optionnelle (ex: Fuite robinet, Panne tableau...)",
  "action_required":"Action concrète à faire (ex: Appel Plombier, Contacter REDAL...)",
  "escalation":     true|false,
  "confidence":     0.0-1.0
}}"""

def validate_and_enrich_response(ia_data: dict, name: str, urgency_level: str,
                                  lang: str, sla_minutes: int) -> dict:
    ia_data.setdefault("sub_category",   "")
    ia_data.setdefault("action_required","")
    ia_data.setdefault("escalation",     False)
    ia_data.setdefault("confidence",     0.75)

    response = ia_data.get("response", "")

    # ── Ajout info SLA pour P0/P1 ─────────────────────────────────────────────
    if urgency_level in ("P0", "P1") and response:
        sla_info = {
            "fr":       f" Une intervention est prévue sous {SLA_LABEL.get(urgency_level, '30 minutes')}.",
            "ar":       f" سيتم التدخل خلال {SLA_LABEL.get(urgency_level, '30 دقيقة')}.",
            "ar_darija":f" Ghadi nssifto wahed l-technician f {SLA_LABEL.get(urgency_level, '30 minutes')}.",
            "en":       f" An intervention is expected within {SLA_LABEL.get(urgency_level, '30 minutes')}.",
        }.get(lang, "")
        if "minute" not in response.lower() and "heure" not in response.lower() \
                and "دقيق" not in response and "minute" not in response:
            ia_data["response"] = response.rstrip(".") + "." + sla_info

    # ── Validation longueur ───────────────────────────────────────────────────
    resp = ia_data.get("response", "")
    if urgency_level == "P0" and len(resp) > 300:
        sentences = re.split(r'(?<=[.!؟])\s+', resp)
        short = ""
        for s in sentences:
            if len(short) + len(s) < 280:
                short += s + " "
            else:
                break
        if short:
            ia_data["response"] = short.strip()

    # ── Validation urgency_level ──────────────────────────────────────────────
    if ia_data.get("urgency_level") not in ("P0", "P1", "P2", "P3"):
        ia_data["urgency_level"] = "P3"

    return ia_data

def compute_confidence(ia_data: dict, forced_urgency: str = None) -> float:
    if forced_urgency:
        return 1.0  

    urgency  = ia_data.get("urgency_level", "P3")
    category = ia_data.get("category", "Autre")
    attempts = ia_data.get("_llm_attempts", 1)

    base_scores = {"P0": 0.85, "P1": 0.82, "P2": 0.75, "P3": 0.70}
    score = base_scores.get(urgency, 0.70)

    if category in ("Autre", "autre", "", None):
        score -= 0.10  
    if attempts > 1:
        score -= 0.10 * (attempts - 1)  
    return round(max(0.0, min(1.0, score)), 2)

async def call_llm_with_retry(client, system_prompt: str, user_message: str,
                               temp_val: float, max_retries: int = 3) -> dict:
    FALLBACK = {
        "response":       "Votre message a bien été reçu. Notre équipe syndic "
                          "va traiter votre demande dans les meilleurs délais.",
        "category":       "Autre",
        "urgency_level":  "P3",
        "sentiment":      "Neutre",
        "sub_category":   "",
        "action_required":"Traitement manuel par le syndic",
        "escalation":     False,
        "confidence":     0.0,
    }
    if not client:
        logger.warning("⚠️ Groq non initialisé — fallback P3")
        return FALLBACK

    last_error = None
    for attempt in range(1, max_retries + 1):
        try:
            completion = client.chat.completions.create(
                model=LLM_MODEL,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user",   "content": user_message},
                ],
                response_format={"type": "json_object"},
                temperature=temp_val,
                max_tokens=800,
            )
            raw     = completion.choices[0].message.content
            cleaned = re.sub(r'^```[a-z]*\n?', '', raw.strip())
            cleaned = re.sub(r'\n?```$',        '', cleaned).strip()
            ia_data = json.loads(cleaned)

            # Validation champs obligatoires
            required = {"response", "category", "urgency_level", "sentiment"}
            missing  = required - ia_data.keys()
            if missing:
                raise ValueError(f"Champs manquants: {missing}")
            if ia_data["urgency_level"] not in ("P0", "P1", "P2", "P3"):
                raise ValueError(f"urgency_level invalide: {ia_data['urgency_level']}")
            if not ia_data["response"] or len(ia_data["response"]) < 5:
                raise ValueError("Réponse trop courte")

            ia_data["_llm_attempts"] = attempt  
            logger.info(f"✅ LLM OK (tentative {attempt}) — "
                  f"{ia_data['urgency_level']} / {ia_data['category']} / "
                  f"conf={ia_data.get('confidence', '?')}")
            return ia_data

        except (json.JSONDecodeError, ValueError) as e:
            last_error = e
            wait = 0.5 * (2 ** (attempt - 1)) 
            logger.warning(f"⚠️ LLM tentative {attempt}/{max_retries}: {e}. Retry dans {wait}s...")
            await asyncio.sleep(wait)  
        except Exception as e:
            logger.error(f"❌ Erreur LLM non-retryable: {e}")
            return FALLBACK

    logger.error(f"❌ LLM échoué après {max_retries} tentatives. Fallback. Erreur: {last_error}")
    return FALLBACK

# ══════════════════════════════════════════════════════════════════════════════
# 10. WEBSOCKET MANAGER
# ══════════════════════════════════════════════════════════════════════════════
class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: str):
        dead = []
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception:
                dead.append(connection)
        for conn in dead:
            self.active_connections.remove(conn)

manager = ConnectionManager()

# ══════════════════════════════════════════════════════════════════════════════
# 11. BASE DE DONNÉES 
# ══════════════════════════════════════════════════════════════════════════════
db_pool: asyncpg.Pool = None
async def init_db():
    if not db_pool:
        return
    try:
        async with db_pool.acquire() as conn:
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS tickets (
                    id                 SERIAL PRIMARY KEY,
                    message_id         VARCHAR(50)  UNIQUE,
                    content_hash       VARCHAR(64),
                    datetime           TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
                    residence_id       VARCHAR(50)  DEFAULT 'RES_GENERAL',
                    phone_number       VARCHAR(64),
                    unit_number        VARCHAR(10),
                    channel            VARCHAR(20)  DEFAULT 'whatsapp',
                    language           VARCHAR(10)  DEFAULT 'fr',
                    has_media          BOOLEAN      DEFAULT FALSE,
                    media_type         VARCHAR(20),
                    text               TEXT,
                    text_clean         TEXT,
                    urgency_level      VARCHAR(5),
                    is_urgent          BOOLEAN      DEFAULT FALSE,
                    category           VARCHAR(50),
                    sub_category       VARCHAR(100),
                    assigned_to        VARCHAR(50)  DEFAULT 'Syndic',
                    sla_target_minutes INT,
                    sentiment          VARCHAR(20),
                    action_required    VARCHAR(200),
                    escalation         BOOLEAN      DEFAULT FALSE,
                    confidence         FLOAT        DEFAULT 0.75,
                    ia_response        TEXT,
                    final_response     TEXT,
                    status             VARCHAR(20)  DEFAULT 'pending',
                    validation_date    TIMESTAMP,
                    validated_by       VARCHAR(100),
                    response_modified  BOOLEAN      DEFAULT FALSE,
                    satisfaction       VARCHAR(10),
                    satisfaction_sent_at TIMESTAMP
                );
            """)
            for idx_sql in [
                "CREATE INDEX IF NOT EXISTS idx_content_hash   ON tickets(content_hash)",
                "CREATE INDEX IF NOT EXISTS idx_phone_number   ON tickets(phone_number)",
                "CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status)",
                "CREATE INDEX IF NOT EXISTS idx_tickets_dt     ON tickets(datetime DESC)",
                "CREATE INDEX IF NOT EXISTS idx_validated_by   ON tickets(validated_by)",
                "CREATE INDEX IF NOT EXISTS idx_residence_status_dt ON tickets(residence_id, status, datetime DESC)",
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_content_hash_unique ON tickets(content_hash) WHERE content_hash IS NOT NULL",
            ]:
                await conn.execute(idx_sql)
            for sql in [
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS content_hash       VARCHAR(64)",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS text_clean         TEXT",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS assigned_to        VARCHAR(50) DEFAULT 'Syndic'",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS sub_category       VARCHAR(100)",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS action_required    VARCHAR(200)",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS escalation         BOOLEAN DEFAULT FALSE",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS confidence         FLOAT   DEFAULT 0.75",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS validated_by       VARCHAR(100)",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS response_modified  BOOLEAN DEFAULT FALSE",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS satisfaction       VARCHAR(10)",
                "ALTER TABLE tickets ADD COLUMN IF NOT EXISTS satisfaction_sent_at TIMESTAMP",
            ]:
                await conn.execute(sql)
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS residences (
                    id           VARCHAR(50)  PRIMARY KEY,
                    name         VARCHAR(100) NOT NULL,
                    city         VARCHAR(100) DEFAULT '',
                    address      VARCHAR(200) DEFAULT '',
                    units_count  INT          DEFAULT 0,
                    created_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
                    created_by   VARCHAR(100) DEFAULT 'system'
                );
            """)
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS residents (
                    id            SERIAL PRIMARY KEY,
                    unit_number   VARCHAR(50)  NOT NULL,
                    name          VARCHAR(100) NOT NULL,
                    phone_number  VARCHAR(50)  NOT NULL,
                    residence_id  VARCHAR(50)  NOT NULL,
                    created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
                );
            """)
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS invite_codes (
                    code       VARCHAR(30)  PRIMARY KEY,
                    label      VARCHAR(100) DEFAULT 'Admin',
                    used_by    VARCHAR(100),
                    is_used    BOOLEAN      DEFAULT FALSE,
                    created_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
                );
            """)
            initial_code = os.getenv("INITIAL_INVITE_CODE")
            if initial_code:
                await conn.execute("""
                    INSERT INTO invite_codes (code, label)
                    VALUES ($1, 'Code Admin Principal')
                    ON CONFLICT (code) DO NOTHING;
                """, initial_code.strip().upper())
                logger.info("✅ Code invite initial inséré depuis .env")
            else:
                logger.warning("⚠️ Aucun INITIAL_INVITE_CODE dans .env — aucun code créé")
        logger.info("✅ Base de données initialisée ")
    except Exception as e:
        logger.error(f"❌ Erreur Init DB: {e}")

# ══════════════════════════════════════════════════════════════════════════════
# 12. VISION IA 
# ══════════════════════════════════════════════════════════════════════════════
async def analyze_image_content(image_url: str) -> str:
    if not groq_client or not image_url:
        return "Image reçue mais non analysée."
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            img_response = await client.get(
                image_url,
                auth=(os.getenv("TWILIO_ACCOUNT_SID"), os.getenv("TWILIO_AUTH_TOKEN")),
            )
        if img_response.status_code != 200:
            return "Image non accessible."

        img_b64   = base64.b64encode(img_response.content).decode("utf-8")
        mime_type = img_response.headers.get("content-type", "image/jpeg")
        # S'assure que le mime_type est valide pour Groq
        if "jpeg" not in mime_type and "png" not in mime_type and "webp" not in mime_type:
            mime_type = "image/jpeg"

        chat = groq_client.chat.completions.create(
            model=VISION_MODEL,          
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:{mime_type};base64,{img_b64}"},
                    },
                    {
                        "type": "text",
                        "text": (
                            "Tu es expert en gestion d'immeuble résidentiel. "
                            "Analyse cette image envoyée par un résident. "
                            "Décris précisément ce que tu vois : type de problème, "
                            "localisation probable, gravité estimée (P0/P1/P2/P3), "
                            "et action recommandée. Sois concis (3-4 phrases max)."
                        ),
                    },
                ],
            }],
            max_tokens=300,
        )
        desc = chat.choices[0].message.content
        logger.info(f"👁️ Vision IA [{VISION_MODEL}]: {desc}")
        return desc
    except Exception as e:
        logger.error(f"❌ Erreur Vision: {e}")
        return "Erreur lors de l'analyse de l'image."

# ══════════════════════════════════════════════════════════════════════════════
# 13. COMMUNICATION
# ══════════════════════════════════════════════════════════════════════════════
async def identify_resident(phone_raw: str):
    if not db_pool:
        return ("Inconnu", "Résident", "RES_GENERAL")
    clean_input    = phone_raw.replace("whatsapp:", "").replace(" ", "").replace("+", "").replace("-", "")
    search_pattern = clean_input[-9:]
    try:
        async with db_pool.acquire() as conn:
            res = await conn.fetchrow(
                """SELECT unit_number, name, residence_id FROM residents
                   WHERE REPLACE(REPLACE(phone_number, ' ', ''), '+', '') LIKE $1""",
                f"%{search_pattern}"
            )
            if res:
                logger.info(f"✅ Résident trouvé: {res['name']} (Appt {res['unit_number']})")
                return (res["unit_number"], res["name"], res["residence_id"])
            logger.info("❌ Résident non trouvé — traitement anonyme.")
            return ("Inconnu", "Résident", "RES_GENERAL")
    except Exception as e:
        logger.warning(f"⚠️ Erreur Identification: {e}")
        return ("Inconnu", "Résident", "RES_GENERAL")

def send_whatsapp_message(to_number: str, message_body: str):
    if not twilio_client:
        logger.warning("⚠️ Twilio non initialisé — message non envoyé")
        return
    try:
        if not to_number.startswith("whatsapp:"):
            to_number = f"whatsapp:{to_number}"
        twilio_client.messages.create(
            from_=twilio_number, to=to_number, body=message_body)
        logger.info(f"✅ WhatsApp envoyé → {to_number}")
    except Exception as e:
        logger.error(f"❌ Twilio Error: {e}")

def send_fcm_alert(ticket_id: int, unit: str, category: str,
                   message_preview: str, urgency: str = "P0",
                   action_required: str = "", escalation: bool = False):
    try:
        emoji = "🚨" if urgency == "P0" else "⚠️"
        esc   = " ↗️ ESCALADE" if escalation else ""
        body  = f"{category}: {message_preview[:60]}"
        if action_required:
            body += f" | Action: {action_required[:40]}"

        msg = messaging.Message(
            notification=messaging.Notification(
                title=f"{emoji} ALERTE {urgency}{esc} — Appt {unit}",
                body=body,
            ),
            data={
                "ticket_id":      str(ticket_id),
                "urgency":        urgency,
                "unit":           unit,
                "category":       category,
                "escalation":     str(escalation).lower(),
                "click_action":   "FLUTTER_NOTIFICATION_CLICK",
            },
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    color="#FF1744" if urgency == "P0" else "#FF6D00",
                    sound="default",
                    channel_id="high_importance_channel",
                ),
            ),
            topic="admin_alerts",
        )
        response = messaging.send(msg)
        logger.info(f"✅ FCM {urgency}{esc} envoyé: {response}")
    except Exception as e:
        logger.warning(f"⚠️ FCM Error (non bloquant): {e}")

# ══════════════════════════════════════════════════════════════════════════════
# 14. ROUTES API
# ══════════════════════════════════════════════════════════════════════════════
# ── A. WebSocket ──────────────────────────────────────────────────────────────
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

# ── B. WEBHOOK WHATSAPP ───────────────────────────────────────────────────────
@app.post("/webhook")
async def receive_whatsapp(request: Request):
    form_data = await request.form()
    form_dict = dict(form_data)

    # ①  Sécurité — Signature Twilio
    if not verify_twilio_signature(request, form_dict):
        logger.warning("🚫 Signature Twilio invalide — requête rejetée")
        return Response(status_code=403)

    From     = form_data.get("From", "")
    Body     = form_data.get("Body", "")
    NumMedia = int(form_data.get("NumMedia", 0))
    # Tronquer les messages trop longs avant tout traitement
    if Body and len(Body) > 3000:
        logger.warning(f"⚠️ Message trop long ({len(Body)} chars) — tronqué à 3000")
        Body = Body[:3000]
    logger.info(f"\n{'═'*60}")
    logger.info(f"📩 Reçu de {From}")

    body_stripped = Body.strip() if Body else ""
    if body_stripped in ("1", "2") and db_pool:
        try:
            async with db_pool.acquire() as conn:
                phone_hash_sat = hash_phone(From)
                sat_row = await conn.fetchrow("""
                    SELECT id, language FROM tickets
                    WHERE phone_number = $1 AND satisfaction = 'sent'
                    ORDER BY satisfaction_sent_at DESC LIMIT 1
                """, phone_hash_sat)
                if sat_row:
                    sat_value = "oui" if body_stripped == "1" else "non"
                    await conn.execute(
                        "UPDATE tickets SET satisfaction=$1 WHERE id=$2",
                        sat_value, sat_row["id"]
                    )
                    sat_lang = sat_row["language"] or "fr"
                    ack = {
                        "oui": {
                            "fr":       "✅ Merci pour votre retour ! Nous sommes ravis que votre problème soit résolu.",
                            "ar":       "✅ شكراً على ردك ! يسعدنا أن مشكلتك قد تم حلها.",
                            "ar_darija":"✅ Barak Allah fik 3la jawabk! Mzyan bzzaf ila tHell l-moshkil dyalk.",
                            "en":       "✅ Thank you! We're glad your issue is resolved.",
                        },
                        "non": {
                            "fr":       "😔 Merci pour votre retour. Nous allons relancer le traitement de votre dossier.",
                            "ar":       "😔 شكراً على ردك. سنعيد النظر في معالجة ملفك.",
                            "ar_darija":"😔 Shukran 3la jawabk. Ghadi n3awdo nshofou l-moshkil dyalk daba.",
                            "en":       "😔 Thank you. We will follow up on your case.",
                        },
                    }[sat_value].get(sat_lang, "")
                    send_whatsapp_message(From, ack)
                    logger.info(f"📊 Satisfaction: ticket#{sat_row['id']} → {sat_value}")
                    return Response(content=str(MessagingResponse()), media_type="application/xml")
        except Exception as e_sat:
            logger.warning(f"⚠️ Satisfaction check error: {e_sat}")

    # ②  Identification résident
    unit, name, res_id = await identify_resident(From)
    logger.info(f"👤 {name} (Appt {unit}) — Résidence: {res_id}")

    # ③  Traitement média
    user_message   = Body
    has_media_bool = False
    media_type_str = None

    if NumMedia > 0:
        has_media_bool = True
        media_type_raw = form_data.get("MediaContentType0", "")
        media_url      = form_data.get("MediaUrl0")
        
        if "audio" in media_type_raw:
            media_type_str = "audio"
            tmp_id   = uuid.uuid4().hex[:8]
            ogg_path = f"temp_{tmp_id}.ogg"
            
            try:
                async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
                    audio_data = await client.get(
                        media_url,
                        auth=(os.getenv("TWILIO_ACCOUNT_SID"), os.getenv("TWILIO_AUTH_TOKEN")),
                    )
                
                with open(ogg_path, "wb") as f:
                    f.write(audio_data.content)

                if len(audio_data.content) < 100:
                    logger.warning(f"⚠️ Fichier audio trop petit ({len(audio_data.content)} bytes) — probablement vide")
                    user_message = f"[Audio non disponible - ref:{tmp_id}]"
                else:
                    with open(ogg_path, "rb") as audio_file:
                        transcription = await async_groq_client.audio.transcriptions.create(
                            file=(ogg_path, audio_file.read()),
                            model="whisper-large-v3",
                            prompt="Transcription d'un message de résident pour le syndic. Peut être en français, arabe ou darija." # Aide l'IA avec le contexte
                        )
                    
                    if transcription and transcription.text:
                        user_message = transcription.text
                        logger.info(f"📝 Audio transcrit (Groq Whisper): '{user_message[:80]}'")
                    else:
                        user_message = f"[Audio non transcrit - ref:{tmp_id}]"
                        logger.warning("⚠️ Transcription audio : Groq n'a renvoyé aucun texte exploitable")

            except Exception as e:
                logger.warning(f"⚠️ Erreur lors de la transcription audio: {e}")
                user_message = f"[Erreur audio - ref:{tmp_id}]"
                
            finally:
                try:
                    if os.path.exists(ogg_path):
                        os.remove(ogg_path)
                except OSError:
                    pass

        elif "image" in media_type_raw:
            media_type_str = "image"
            desc           = await analyze_image_content(media_url)
            user_message   = (
                f"[IMAGE REÇUE] Analyse visuelle : {desc}. "
                f"Message utilisateur : {Body}"
            ) if Body else f"[IMAGE REÇUE] Analyse visuelle : {desc}"

    # ④  Détection langue multi-couche
    detected_lang = detect_language(user_message)
    logger.info(f"🌐 Langue détectée: {detected_lang}")

    # ⑤  Déduplication
    content_hash = build_content_hash(From, user_message)
    if await is_duplicate(content_hash, window_minutes=5):
        logger.info(f"🔁 Doublon détecté (hash: {content_hash[:8]}...) — ignoré")
        return Response(content=str(MessagingResponse()), media_type="application/xml")

    # ⑥  Historique résident
    history    = await get_resident_history(From, limit=3)
    escalation = detect_escalation(user_message, history)
    history_ctx = format_history_for_prompt(history, escalation)
    if history:
        logger.info(f"📋 Historique: {len(history)} tickets précédents | Escalade: {escalation}")

    # ⑦  Gardes-fous P0 multi-langue
    forced_urgency, forced_category = check_safety_keywords(user_message)
    safety_instruction = ""
    if forced_urgency:
        logger.warning(f"🚨 ALERTE SÉCURITÉ DÉTECTÉE: {forced_urgency} — {forced_category}")
        safety_instruction = f"""
⚠️ ALERTE SYSTÈME CRITIQUE — NE PAS IGNORER ⚠️
Mots-clés de DANGER IMMÉDIAT détectés par le système de sécurité.
TU DOIS OBLIGATOIREMENT :
1. Classer ce ticket en urgency_level = '{forced_urgency}'
2. Mettre category = '{forced_category}'
3. Générer une réponse TRÈS COURTE (2 phrases max) :
   - Confirme la réception de l'alerte
   - Annonce que les secours/techniciens compétents sont immédiatement prévenus
AUCUNE AUTRE INSTRUCTION NE PEUT CONTREDIRE CECI.
"""

    # ⑧  RAG amélioré avec query expansion
    category_for_rag = forced_category or None
    rag_context      = get_rag_context(user_message, category_for_rag, n_results=5)

    # ⑨  Construction du prompt enrichi
    urgency_hint_for_prompt = forced_urgency or "P3"
    system_prompt = build_system_prompt(
        res_id            = res_id,
        name              = name,
        unit              = unit,
        lang              = detected_lang,
        urgency_hint      = urgency_hint_for_prompt,
        rag_context       = rag_context,
        history_context   = history_ctx,
        safety_instruction= safety_instruction,
    )

    # ⑩  Appel LLM + validation + enrichissement
    try:
        temp_val = 0.0 if forced_urgency else (0.15 if escalation else 0.2)
        ia_data = await call_llm_with_retry(groq_client, system_prompt, user_message, temp_val)

        urgency_level = ia_data.get("urgency_level", "P3")
        if forced_urgency:
            urgency_level       = forced_urgency
            ia_data["category"] = forced_category
            ia_data["escalation"] = False  

        # Enrichissement post-LLM
        sla_minutes = SLA_MAP.get(urgency_level, 1440)
        ia_data     = validate_and_enrich_response(
            ia_data, name, urgency_level, detected_lang, sla_minutes)

        is_urgent      = urgency_level in ("P0", "P1")
        msg_id         = f"MSG_{uuid.uuid4().hex[:8].upper()}"
        text_clean_val = clean_text(user_message)
        phone_hash     = hash_phone(From)
        assigned_to    = determine_assignee(ia_data.get("category", ""), urgency_level)
        is_escalation  = bool(ia_data.get("escalation") or escalation)

        # ⑪  Logique d'auto-réponse
        if urgency_level in ("P0", "P1"):
            final_status        = "pending"
            final_response_text = None
            logger.info(f"🛑 ALERTE {urgency_level}: Validation humaine requise.")
        elif is_escalation and urgency_level == "P2":
            final_status        = "pending"
            final_response_text = None
            logger.info(f"↗️ ESCALADE P2: Validation humaine requise.")
        else:
            final_status        = "validated"
            final_response_text = ia_data.get("response")
            send_whatsapp_message(From, final_response_text)
            logger.info(f"🤖 AUTO-RÉPONSE {urgency_level} envoyée.")

        computed_conf = compute_confidence(ia_data, forced_urgency=forced_urgency)
        ia_data["confidence"] = computed_conf
        logger.info(f"📊 Classification: {urgency_level} | {ia_data.get('category')} | "
                    f"conf={computed_conf:.2f} | esc={is_escalation}")

        # ⑫  INSERT en base (asyncpg)
        if db_pool:
            async with db_pool.acquire() as conn:
                ticket_db_id = await conn.fetchval("""
                    INSERT INTO tickets (
                        message_id, content_hash, phone_number,
                        unit_number, residence_id, urgency_level,
                        is_urgent, category, sub_category,
                        assigned_to, sentiment, sla_target_minutes,
                        has_media, media_type, text,
                        text_clean, ia_response, final_response,
                        status, language, action_required,
                        escalation, confidence
                    ) VALUES (
                        $1,  $2,  $3,
                        $4,  $5,  $6,
                        $7,  $8,  $9,
                        $10, $11, $12,
                        $13, $14, $15,
                        $16, $17, $18,
                        $19, $20, $21,
                        $22, $23
                    ) RETURNING id
                """,
                    msg_id,                          content_hash,
                    phone_hash,                      unit,
                    res_id,                          urgency_level,
                    is_urgent,                       ia_data.get("category"),
                    ia_data.get("sub_category"),     assigned_to,
                    ia_data.get("sentiment"),        sla_minutes,
                    has_media_bool,                  media_type_str,
                    user_message,                    text_clean_val,
                    ia_data.get("response"),         final_response_text,
                    final_status,                    detected_lang,
                    ia_data.get("action_required"),  is_escalation,
                    float(ia_data.get("confidence", 0.75)),
                )
                if not ticket_db_id:
                    logger.warning(f"Doublon détecté pour le hash {content_hash}. Ignoré.")
                    return Response(content="<Response></Response>", media_type="application/xml")
                logger.info(f"✅ Ticket {msg_id} inséré (id={ticket_db_id}) | {urgency_level} | {assigned_to}")

            if ticket_db_id and (urgency_level in ("P0","P1") or (is_escalation and urgency_level=="P2")):
                send_fcm_alert(
                    ticket_id       = ticket_db_id,
                    unit            = unit,
                    category        = ia_data.get("category", "Autre"),
                    message_preview = user_message[:80],
                    urgency         = urgency_level,
                    action_required = ia_data.get("action_required", ""),
                    escalation      = is_escalation,
                )
            await manager.broadcast("REFRESH")

    except Exception as e:
        logger.error(f"❌ Erreur pipeline: {e}")
        import traceback; traceback.print_exc()
        if db_pool:
            try:
                async with db_pool.acquire() as conn:
                    await conn.execute(
                        "INSERT INTO tickets (phone_number, text, status) VALUES ($1, $2, 'error')",
                        hash_phone(From), user_message,
                )
            except Exception as e_insert:
                logger.error(f"❌ INSERT ticket échoué: {e_insert}")

    return Response(content=str(MessagingResponse()), media_type="application/xml")

# ══════════════════════════════════════════════════════════════════════════════
# 15. API FLUTTER — Résidences, Grille, Validation
# ══════════════════════════════════════════════════════════════════════════════
@app.get("/api/residences-list")
async def get_residences_list(user=Depends(verify_token)):
    if not db_pool:
        return []
    try:
        async with db_pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT id, name, city, address, units_count
                FROM residences ORDER BY created_at DESC
            """)
            results = [
                {
                    "id":          r["id"],
                    "name":        r["name"],
                    "city":        r["city"] or "",
                    "address":     r["address"] or "",
                    "units_count": r["units_count"] or 0,
                }
                for r in rows
            ]
            orphan_rows = await conn.fetch(
                "SELECT DISTINCT residence_id FROM residents ORDER BY residence_id"
            )
            table_ids = {r["id"] for r in results}
            for row in orphan_rows:
                rid = row["residence_id"]
                if rid and rid not in table_ids:
                    results.append({
                        "id":          rid,
                        "name":        rid.replace("RES_", "").replace("_", " ").title(),
                        "city":        "",
                        "address":     "",
                        "units_count": 0,
                    })
            return results or [{"id": "RES_GENERAL", "name": "Résidence Générale",
                                 "city": "", "address": "", "units_count": 0}]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/residences")
async def create_residence(residence: ResidenceModel, user=Depends(verify_token)):
    admin_email = user.get("email") or user.get("uid", "system")
    name_clean  = residence.name.strip()
    if not name_clean:
        raise HTTPException(status_code=400, detail="Le nom de la résidence est requis")
    import unicodedata as _ud
    normalized  = _ud.normalize("NFD", name_clean)
    normalized  = "".join(c for c in normalized if _ud.category(c) != "Mn")
    normalized  = re.sub(r"[^a-zA-Z0-9\s]", "", normalized)
    normalized  = re.sub(r"\s+", "_", normalized.strip()).upper()
    residence_id = f"RES_{normalized[:30]}"
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            existing = await conn.fetchrow("SELECT id FROM residences WHERE id = $1", residence_id)
            if existing:
                count = await conn.fetchval("SELECT COUNT(*) FROM residences WHERE id LIKE $1", f"{residence_id}%")
                residence_id = f"{residence_id}_{count + 1}"
            await conn.execute("""
                INSERT INTO residences (id, name, city, address, units_count, created_by)
                VALUES ($1, $2, $3, $4, $5, $6)
            """, residence_id, name_clean, residence.city.strip(),
                residence.address.strip(), residence.units_count, admin_email)
        logger.info(f"✅ Résidence créée : {residence_id} par {admin_email}")
        return {"id": residence_id, "name": name_clean, "city": residence.city.strip(),
                "address": residence.address.strip(), "units_count": residence.units_count}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/residences/{residence_id}")
async def delete_residence(residence_id: str, user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            async with conn.transaction():
                await conn.execute("DELETE FROM residents  WHERE residence_id = $1", residence_id)
                result = await conn.execute("DELETE FROM residences WHERE id = $1", residence_id)
                if result == "DELETE 0":
                    raise HTTPException(status_code=404, detail="Résidence introuvable")
        return {"status": "ok", "deleted": residence_id}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/grid-status")
async def get_grid_status(residence_id: str = None, user=Depends(verify_token)):
    if not db_pool:
        return []
    try:
        async with db_pool.acquire() as conn:
            sql = """
                SELECT t.id, t.unit_number, t.text, t.ia_response,
                       t.urgency_level, r.phone_number, t.assigned_to,
                       t.category, t.sub_category, t.action_required,
                       t.escalation, t.confidence
                FROM tickets t
                LEFT JOIN residents r
                       ON r.unit_number  = t.unit_number
                      AND r.residence_id = t.residence_id
                WHERE t.status = 'pending'
            """
            if residence_id:
                sql += " AND t.residence_id = $1 ORDER BY t.datetime DESC"
                rows = await conn.fetch(sql, residence_id)
            else:
                sql += " ORDER BY t.datetime DESC"
                rows = await conn.fetch(sql)
            return [
                {
                    "id":             r["id"],
                    "unit":           r["unit_number"],
                    "message":        r["text"],
                    "ia_response":    r["ia_response"],
                    "urgence":        "Critique" if r["urgency_level"] in ("P0","P1") else "Faible",
                    "urgency_level":  r["urgency_level"],
                    "phone":          r["phone_number"] or "",
                    "assigned_to":    r["assigned_to"] or "Syndic",
                    "category":       r["category"] or "Autre",
                    "sub_category":   r["sub_category"] or "",
                    "action_required":r["action_required"] or "",
                    "escalation":     bool(r["escalation"]),
                    "confidence":     float(r["confidence"] or 0.75),
                }
                for r in rows
            ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/validate-ticket")
async def validate_ticket(req: ValidationRequest, user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        admin_email = user.get("email") or user.get("uid", "system")
        async with db_pool.acquire() as conn:
            async with conn.transaction():
                row = await conn.fetchrow(
                    "SELECT ia_response, language FROM tickets WHERE id = $1", req.ticket_id)
                if not row:
                    raise HTTPException(status_code=404, detail="Ticket introuvable")
                was_modified = bool(row["ia_response"] and req.text != row["ia_response"])
                ticket_lang  = row["language"] or "fr"

                await conn.execute("""
                    UPDATE tickets
                    SET status            = 'validated',
                        final_response    = $1,
                        validation_date   = NOW(),
                        validated_by      = $2,
                        response_modified = $3
                    WHERE id = $4
                """, req.text, admin_email, was_modified, req.ticket_id)

        send_whatsapp_message(req.phone, req.text)
        await manager.broadcast("REFRESH")
        logger.info(f"✅ Ticket {req.ticket_id} validé par {admin_email} | modifié={was_modified}")
        return {"status": "ok", "modified": was_modified}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ══════════════════════════════════════════════════════════════════════════════
# 16. RÉSIDENTS CRUD
# ══════════════════════════════════════════════════════════════════════════════
@app.get("/api/residents")
async def get_residents(residence_id: str, user=Depends(verify_token)):
    if not db_pool:
        return []
    try:
        async with db_pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT unit_number, name, phone_number FROM residents
                WHERE residence_id = $1 ORDER BY unit_number
            """, residence_id)
            return [{"unit": r["unit_number"], "name": r["name"], "phone": r["phone_number"]}
                    for r in rows]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/residents")
async def add_resident(resident: ResidentModel, user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500, detail="DB indisponible")
    try:
        async with db_pool.acquire() as conn:
            await conn.execute(
                "INSERT INTO residents (unit_number, name, phone_number, residence_id) VALUES ($1,$2,$3,$4)",
                resident.unit, resident.name, resident.phone, resident.residence_id,
            )
        return {"message": "Résident ajouté"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/residents/{unit}")
async def update_resident(unit: str, resident: UpdateResidentModel, user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500, detail="DB indisponible")
    try:
        async with db_pool.acquire() as conn:
            result = await conn.execute("""
                UPDATE residents SET unit_number=$1, name=$2, phone_number=$3
                WHERE unit_number=$4 AND residence_id=$5
            """, resident.new_unit, resident.new_name, resident.new_phone,
                resident.old_unit, resident.residence_id)
        if result == "UPDATE 0":
            raise HTTPException(status_code=404, detail="Résident introuvable")
        return {"message": "Résident modifié"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/residents/{unit}")
async def delete_resident(unit: str, residence_id: str, user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            await conn.execute(
                "DELETE FROM residents WHERE unit_number=$1 AND residence_id=$2",
                unit, residence_id,
            )
        return {"status": "deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ══════════════════════════════════════════════════════════════════════════════
# 17. BROADCAST & RÈGLES
# ══════════════════════════════════════════════════════════════════════════════
@app.post("/api/broadcast")
async def send_broadcast(req: BroadcastRequest, user=Depends(verify_token)):
    # Rate limit par utilisateur — max 10 broadcasts/heure pour éviter le spam
    admin_uid = user.get("uid", "unknown")
    if _redis_client:
        rl_key = f"broadcast_rl:{admin_uid}"
        now    = int(time.time())
        try:
            pipe = _redis_client.pipeline()
            pipe.zremrangebyscore(rl_key, 0, now - 3600)
            pipe.zcard(rl_key)
            pipe.zadd(rl_key, {str(now): now})
            pipe.expire(rl_key, 3605)
            results = pipe.execute()
            if results[1] >= 10:
                raise HTTPException(
                    status_code=429,
                    detail="Trop de broadcasts — maximum 10 par heure"
                )
        except HTTPException:
            raise
        except Exception:
            pass  # Redis indisponible → dégradé gracieux
    if not db_pool:
        return {"error": "DB connection failed"}
    try:
        async with db_pool.acquire() as conn:
            residents_rows = await conn.fetch(
                "SELECT phone_number FROM residents WHERE residence_id = $1", req.residence_id)
    except Exception as e:
        return {"error": str(e)}

    count = 0
    for res in residents_rows:
        raw   = str(res["phone_number"]).strip()
        phone = raw
        if not phone.startswith("whatsapp:"):
            if phone.startswith("0"):
                phone = "+212" + phone[1:]
            elif not phone.startswith("+"):
                phone = "+212" + phone
            phone = f"whatsapp:{phone}"
        try:
            twilio_client.messages.create(
                from_=twilio_number, body=f"📢 Annonce Syndic :\n\n{req.message}", to=phone)
            count += 1
        except Exception as e:
            logger.error(f"❌ Broadcast Twilio {phone}: {e}")
    return {"status": "ok", "sent_to": count}

@app.post("/api/add-rule")
async def add_rule(req: RuleRequest, user=Depends(verify_token)):
    # Rate limit — max 20 règles/heure par admin
    admin_uid = user.get("uid", "unknown")
    if _redis_client:
        rl_key = f"addrule_rl:{admin_uid}"
        now    = int(time.time())
        try:
            pipe = _redis_client.pipeline()
            pipe.zremrangebyscore(rl_key, 0, now - 3600)
            pipe.zcard(rl_key)
            pipe.zadd(rl_key, {str(now): now})
            pipe.expire(rl_key, 3605)
            results = pipe.execute()
            if results[1] >= 20:
                raise HTTPException(
                    status_code=429,
                    detail="Trop de règles ajoutées — maximum 20 par heure"
                )
        except HTTPException:
            raise
        except Exception:
            pass
    try:
        if not collection:
            raise HTTPException(status_code=503, detail="ChromaDB non disponible")
        enriched = f"[URGENCE:P3 | CATÉGORIE:administratif]\n{req.rule}"
        collection.add(
            documents=[enriched],
            ids=[str(uuid.uuid4())],
            metadatas=[{"source": "admin_rule", "urgency": "P3", "category": "administratif"}],
        )
        logger.info(f"🧠 Règle ajoutée: {req.rule[:80]}")
        return {"status": "Rule added"}
    except HTTPException:
        raise
    except Exception as e:
        return {"error": str(e)}

# ══════════════════════════════════════════════════════════════════════════════
# 18. HISTORIQUE
# ══════════════════════════════════════════════════════════════════════════════
@app.get("/api/history")
async def get_history(limit: int = 100, offset: int = 0, days: int = 30, user=Depends(verify_token)):
    if not db_pool:
        return []
    try:
        async with db_pool.acquire() as conn:
            safe_limit = min(limit, 200) # Sécurité : max 200 éléments par page
            
            if days > 0:
                rows = await conn.fetch("""
                    SELECT id, unit_number, text, urgency_level, category,
                           status, datetime, final_response, assigned_to,
                           sub_category, escalation, confidence, language
                    FROM tickets
                    WHERE datetime >= NOW() - ($1 * INTERVAL '1 day')
                    ORDER BY datetime DESC LIMIT $2 OFFSET $3
                """, days, safe_limit, offset)
            else:
                rows = await conn.fetch("""
                    SELECT id, unit_number, text, urgency_level, category,
                           status, datetime, final_response, assigned_to,
                           sub_category, escalation, confidence, language
                    FROM tickets 
                    ORDER BY datetime DESC LIMIT $1 OFFSET $2
                """, safe_limit, offset)
                
            return [
                {
                    "id":           r["id"],
                    "unit":         r["unit_number"],
                    "message":      r["text"],
                    "urgency":      r["urgency_level"],
                    "category":     r["category"],
                    "status":       r["status"],
                    "date":         r["datetime"].strftime("%d/%m %H:%M") if r["datetime"] else "",
                    "response":     r["final_response"],
                    "assigned_to":  r["assigned_to"] or "Syndic",
                    "sub_category": r["sub_category"] or "",
                    "escalation":   bool(r["escalation"]),
                    "confidence":   float(r["confidence"] or 0.75),
                    "language":     r["language"] or "fr",
                }
                for r in rows
            ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ══════════════════════════════════════════════════════════════════════════════
# 19. ANALYTICS
# ══════════════════════════════════════════════════════════════════════════════
@app.get("/api/analytics")
async def get_analytics(days: int = 30, user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            if days > 0:
                r = await conn.fetchrow("""
                    SELECT
                    COUNT(*)                                            AS total,
                    SUM(CASE WHEN is_urgent          THEN 1 ELSE 0 END) AS urgent,
                    SUM(CASE WHEN urgency_level='P0' THEN 1 ELSE 0 END) AS p0,
                    SUM(CASE WHEN urgency_level='P1' THEN 1 ELSE 0 END) AS p1,
                    SUM(CASE WHEN urgency_level='P2' THEN 1 ELSE 0 END) AS p2,
                    SUM(CASE WHEN urgency_level='P3' THEN 1 ELSE 0 END) AS p3,
                    SUM(CASE WHEN status='validated' THEN 1 ELSE 0 END) AS validated,
                    SUM(CASE WHEN status='pending'   THEN 1 ELSE 0 END) AS pending,
                    SUM(CASE WHEN escalation=TRUE    THEN 1 ELSE 0 END) AS escalations,
                    ROUND(AVG(confidence)::numeric, 2)                  AS avg_confidence
                FROM tickets WHERE datetime >= NOW() - ($1 * INTERVAL '1 day')
                """, days)
            else:
                r = await conn.fetchrow("""
                    SELECT
                    COUNT(*)                                            AS total,
                    SUM(CASE WHEN is_urgent          THEN 1 ELSE 0 END) AS urgent,
                    SUM(CASE WHEN urgency_level='P0' THEN 1 ELSE 0 END) AS p0,
                    SUM(CASE WHEN urgency_level='P1' THEN 1 ELSE 0 END) AS p1,
                    SUM(CASE WHEN urgency_level='P2' THEN 1 ELSE 0 END) AS p2,
                    SUM(CASE WHEN urgency_level='P3' THEN 1 ELSE 0 END) AS p3,
                    SUM(CASE WHEN status='validated' THEN 1 ELSE 0 END) AS validated,
                    SUM(CASE WHEN status='pending'   THEN 1 ELSE 0 END) AS pending,
                    SUM(CASE WHEN escalation=TRUE    THEN 1 ELSE 0 END) AS escalations,
                    ROUND(AVG(confidence)::numeric, 2)                  AS avg_confidence
                    FROM tickets
                """)
            summary = {k: (float(r[k]) if k == "avg_confidence" else int(r[k] or 0))
                       for k in ["total","urgent","p0","p1","p2","p3",
                                  "validated","pending","escalations","avg_confidence"]}

            sla_rows_raw = await conn.fetch("""
                SELECT urgency_level, COUNT(*) AS total,
                    SUM(CASE WHEN validation_date IS NOT NULL
                         AND EXTRACT(EPOCH FROM (validation_date - datetime))/60
                             <= sla_target_minutes THEN 1 ELSE 0 END) AS respected
                FROM tickets WHERE status = 'validated' GROUP BY urgency_level
            """)
            sla_rows = {r["urgency_level"]: {"total": int(r["total"] or 0), "respected": int(r["respected"] or 0)}
                        for r in sla_rows_raw}
            sla = {
                "p0_total": sla_rows.get("P0", {}).get("total", 0),
                "p0_respected": sla_rows.get("P0", {}).get("respected", 0),
                "p1_total": sla_rows.get("P1", {}).get("total", 0),
                "p1_respected": sla_rows.get("P1", {}).get("respected", 0),
                "p2_total": sla_rows.get("P2", {}).get("total", 0),
                "p2_respected": sla_rows.get("P2", {}).get("respected", 0),
                "p3_total": sla_rows.get("P3", {}).get("total", 0),
                "p3_respected": sla_rows.get("P3", {}).get("respected", 0),
            }

            by_category = [
                {"category": r["category"], "count": int(r["count"])}
                for r in await conn.fetch("""
                    SELECT category, COUNT(*) AS count FROM tickets
                    WHERE category IS NOT NULL GROUP BY category ORDER BY 2 DESC LIMIT 15""")
            ]
            by_sentiment = [
                {"sentiment": r["sentiment"], "count": int(r["count"])}
                for r in await conn.fetch("""
                    SELECT sentiment, COUNT(*) AS count FROM tickets
                    WHERE sentiment IS NOT NULL GROUP BY sentiment ORDER BY 2 DESC""")
            ]
            urgency_by_category = [
                {"category": r["category"],
                 "p0": int(r["p0"] or 0), "p1": int(r["p1"] or 0),
                 "p2": int(r["p2"] or 0), "p3": int(r["p3"] or 0)}
                for r in await conn.fetch("""
                    SELECT category,
                        SUM(CASE WHEN urgency_level='P0' THEN 1 ELSE 0 END) AS p0,
                        SUM(CASE WHEN urgency_level='P1' THEN 1 ELSE 0 END) AS p1,
                        SUM(CASE WHEN urgency_level='P2' THEN 1 ELSE 0 END) AS p2,
                        SUM(CASE WHEN urgency_level='P3' THEN 1 ELSE 0 END) AS p3
                    FROM tickets WHERE category IS NOT NULL GROUP BY category
                    ORDER BY (SUM(CASE WHEN urgency_level='P0' THEN 1 ELSE 0 END) + SUM(CASE WHEN urgency_level='P1' THEN 1 ELSE 0 END)) DESC LIMIT 10""")
            ]
            by_status = [
                {"status": r["status"], "count": int(r["count"])}
                for r in await conn.fetch(
                    "SELECT status, COUNT(*) AS count FROM tickets GROUP BY status ORDER BY 2 DESC")
            ]
            daily_trend = [
                {"date": r["day"].strftime("%Y-%m-%d"), "total": int(r["total"] or 0),
                 "p0": int(r["p0"] or 0), "p1": int(r["p1"] or 0), "validated": int(r["validated"] or 0)}
                for r in await conn.fetch("""
                    SELECT DATE(datetime) AS day, COUNT(*) AS total,
                        SUM(CASE WHEN urgency_level='P0' THEN 1 ELSE 0 END) AS p0,
                        SUM(CASE WHEN urgency_level='P1' THEN 1 ELSE 0 END) AS p1,
                        SUM(CASE WHEN status='validated' THEN 1 ELSE 0 END) AS validated
                    FROM tickets WHERE datetime >= NOW() - INTERVAL '30 days'
                    GROUP BY day ORDER BY day DESC""")
            ]
            by_residence = [
                {"residence_id": r["residence_id"], "total": int(r["total"] or 0), "urgent": int(r["urgent"] or 0)}
                for r in await conn.fetch("""
                    SELECT residence_id, COUNT(*) AS total,
                        SUM(CASE WHEN is_urgent THEN 1 ELSE 0 END) AS urgent
                    FROM tickets WHERE residence_id IS NOT NULL
                    GROUP BY residence_id ORDER BY total DESC""")
            ]
            pending_tickets = [
                {"id": r["id"], "unit": r["unit_number"] or "?",
                 "message": (r["text"] or "")[:120],
                 "urgency_level": r["urgency_level"] or "P3",
                 "date": r["datetime"].strftime("%d/%m %H:%M") if r["datetime"] else "",
                 "assigned_to": r["assigned_to"] or "Syndic",
                 "escalation": bool(r["escalation"])}
                for r in await conn.fetch("""
                    SELECT id, unit_number, text, urgency_level, datetime, assigned_to, escalation
                    FROM tickets WHERE status='pending'
                    ORDER BY CASE urgency_level WHEN 'P0' THEN 1 WHEN 'P1' THEN 2
                                               WHEN 'P2' THEN 3 ELSE 4 END, datetime ASC
                    LIMIT 5""")
            ]
            by_assignee = [
                {"assigned_to": r["assigned_to"], "total": int(r["cnt"] or 0),
                 "done": int(r["done"] or 0), "pending": int(r["pending_count"] or 0)}
                for r in await conn.fetch("""
                    SELECT assigned_to, COUNT(*) AS cnt,
                        SUM(CASE WHEN status='validated' THEN 1 ELSE 0 END) AS done,
                        SUM(CASE WHEN status='pending'   THEN 1 ELSE 0 END) AS pending_count
                    FROM tickets WHERE assigned_to IS NOT NULL
                    GROUP BY assigned_to ORDER BY cnt DESC""")
            ]
            by_language = [
                {"language": r["language"], "count": int(r["count"])}
                for r in await conn.fetch("""
                    SELECT language, COUNT(*) AS count FROM tickets
                    WHERE language IS NOT NULL GROUP BY language ORDER BY 2 DESC""")
            ]
            return {
                "summary": summary, "sla": sla, "by_category": by_category,
                "by_sentiment": by_sentiment, "urgency_by_category": urgency_by_category,
                "by_status": by_status, "daily_trend": daily_trend,
                "by_residence": by_residence, "pending_tickets": pending_tickets,
                "by_assignee": by_assignee, "by_language": by_language,
            }
    except Exception as e:
        logger.error(f"❌ Erreur analytics: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ══════════════════════════════════════════════════════════════════════════════
# 20. ENDPOINTS DIVERS
# ══════════════════════════════════════════════════════════════════════════════
@app.post("/api/verify-invite-code")
async def verify_invite_code(req: InviteCodeRequest, request: Request):
    client_ip  = request.client.host if request.client else "unknown"
    if not check_ip_rate_limit(client_ip, max_attempts=5, window_seconds=3600):
        raise HTTPException(status_code=429, detail="Trop de tentatives. Réessayez dans une heure.")
    code_clean = req.code.strip().upper()
    if not code_clean or len(code_clean) > 30:
        raise HTTPException(status_code=400, detail="Format de code invalide")
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            row = await conn.fetchrow("SELECT code, is_used FROM invite_codes WHERE code = $1", code_clean)
            if not row:
                raise HTTPException(status_code=404, detail="Code invalide")
            if row["is_used"]:
                raise HTTPException(status_code=409, detail="Code déjà utilisé")
            return {"valid": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/use-invite-code")
async def use_invite_code(req: UseInviteCodeRequest, user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            result = await conn.execute(
                "UPDATE invite_codes SET is_used=TRUE, used_by=$1 WHERE code=$2 AND is_used=FALSE",
                req.email, req.code.strip().upper())
            if result == "UPDATE 0":
                raise HTTPException(status_code=409, detail="Code déjà utilisé")
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/create-invite-code")
async def create_invite_code(label: str = "Admin", user=Depends(verify_token)):
    import secrets as _sec, string as _str
    code = "SYN-" + "".join(_sec.choice(_str.ascii_uppercase + _str.digits) for _ in range(10))
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            await conn.execute("INSERT INTO invite_codes (code, label) VALUES ($1, $2)", code, label)
        return {"code": code, "label": label}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/pending-count")
async def get_pending_count(residence_id: str = None, user=Depends(verify_token)):
    if not db_pool:
        return {"count": 0, "p0": 0}
    try:
        async with db_pool.acquire() as conn:
            if residence_id:
                r = await conn.fetchrow("""
                    SELECT COUNT(*),
                           SUM(CASE WHEN urgency_level='P0' THEN 1 ELSE 0 END) AS p0
                    FROM tickets WHERE status='pending' AND residence_id=$1
                """, residence_id)
            else:
                r = await conn.fetchrow("""
                    SELECT COUNT(*),
                           SUM(CASE WHEN urgency_level='P0' THEN 1 ELSE 0 END) AS p0
                    FROM tickets WHERE status='pending'
                """)
            return {"count": int(r[0] or 0), "p0": int(r[1] or 0)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/tickets/{ticket_id}")
async def get_ticket_detail(ticket_id: int, user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            r = await conn.fetchrow("""
                SELECT id, message_id, datetime, residence_id, unit_number,
                       language, has_media, media_type, text, text_clean,
                       urgency_level, is_urgent, category, sub_category,
                       assigned_to, sla_target_minutes, sentiment, ia_response,
                       final_response, status, validation_date,
                       action_required, escalation, confidence
                FROM tickets WHERE id = $1
            """, ticket_id)
        if not r:
            raise HTTPException(status_code=404, detail="Ticket introuvable")
        sla_ok = None
        if r["validation_date"] and r["datetime"]:
            elapsed = (r["validation_date"] - r["datetime"]).total_seconds() / 60
            sla_ok  = elapsed <= (r["sla_target_minutes"] or 1440)
        return {
            "id":              r["id"],
            "message_id":      r["message_id"],
            "datetime":        r["datetime"].isoformat() if r["datetime"] else None,
            "residence_id":    r["residence_id"],
            "unit":            r["unit_number"],
            "language":        r["language"],
            "has_media":       r["has_media"],
            "media_type":      r["media_type"],
            "text":            r["text"],
            "text_clean":      r["text_clean"],
            "urgency_level":   r["urgency_level"],
            "is_urgent":       r["is_urgent"],
            "category":        r["category"],
            "sub_category":    r["sub_category"],
            "assigned_to":     r["assigned_to"],
            "sla_minutes":     r["sla_target_minutes"],
            "sentiment":       r["sentiment"],
            "ia_response":     r["ia_response"],
            "final_response":  r["final_response"],
            "status":          r["status"],
            "validation_date": r["validation_date"].isoformat() if r["validation_date"] else None,
            "sla_respected":   sla_ok,
            "action_required": r["action_required"],
            "escalation":      bool(r["escalation"]),
            "confidence":      float(r["confidence"] or 0.75),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/units")
async def get_units(residence_id: str, user=Depends(verify_token)):
    if not db_pool:
        return []
    try:
        async with db_pool.acquire() as conn:
            rows = await conn.fetch(
                "SELECT unit_number, name FROM residents WHERE residence_id=$1 ORDER BY unit_number",
                residence_id)
            return [{"unit": r["unit_number"], "name": r["name"]} for r in rows]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/admin-stats")
async def get_admin_stats(user=Depends(verify_token)):
    email = user.get("email") or user.get("uid", "unknown")
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            validated  = await conn.fetchval("SELECT COUNT(*) FROM tickets WHERE validated_by=$1", email)
            modified   = await conn.fetchval(
                "SELECT COUNT(*) FROM tickets WHERE validated_by=$1 AND response_modified=TRUE", email)
            p0_handled = await conn.fetchval(
                "SELECT COUNT(*) FROM tickets WHERE validated_by=$1 AND urgency_level='P0'", email)
            avg_val    = await conn.fetchval("""
                SELECT AVG(EXTRACT(EPOCH FROM (validation_date - datetime)) / 60)
                FROM tickets WHERE validated_by=$1 AND validation_date IS NOT NULL
            """, email)
        return {
            "tickets_validated":      int(validated or 0),
            "tickets_modified":       int(modified or 0),
            "p0_handled":             int(p0_handled or 0),
            "avg_validation_minutes": round(float(avg_val or 0), 1),
            "total_actions":          int(validated or 0),
            "admin_email":            email,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ══════════════════════════════════════════════════════════════════════════════
# 21. SATISFACTION RÉSIDENTE
# ══════════════════════════════════════════════════════════════════════════════
@app.get("/api/satisfaction-stats")
async def get_satisfaction_stats(user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            r = await conn.fetchrow("""
                SELECT
                    COUNT(*) FILTER (WHERE satisfaction = 'oui')                     AS satisfied,
                    COUNT(*) FILTER (WHERE satisfaction = 'non')                     AS not_satisfied,
                    COUNT(*) FILTER (WHERE satisfaction = 'sent')                    AS awaiting,
                    COUNT(*) FILTER (WHERE satisfaction IS NULL AND status = 'validated') AS not_sent
                FROM tickets
            """)
        satisfied     = int(r["satisfied"] or 0)
        not_satisfied = int(r["not_satisfied"] or 0)
        awaiting      = int(r["awaiting"] or 0)
        not_sent      = int(r["not_sent"] or 0)
        total_answered = satisfied + not_satisfied
        rate = round(satisfied / total_answered * 100, 1) if total_answered > 0 else None
        return {
            "satisfied":         satisfied,
            "not_satisfied":     not_satisfied,
            "awaiting":          awaiting,
            "not_sent":          not_sent,
            "total_answered":    total_answered,
            "satisfaction_rate": rate,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/send-satisfaction")
async def send_satisfaction_messages(user=Depends(verify_token)):
    if not db_pool:
        raise HTTPException(status_code=500)
    try:
        async with db_pool.acquire() as conn:
            result = await conn.execute("""
                UPDATE tickets
                SET satisfaction = 'sent', satisfaction_sent_at = NOW()
                WHERE status = 'validated'
                  AND satisfaction IS NULL
                  AND validation_date IS NOT NULL
                  AND validation_date < NOW() - INTERVAL '24 hours'
            """)
        sent_count = int(result.split()[-1])
        return {"status": "ok", "marked_sent": sent_count}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
# ══════════════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)