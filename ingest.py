import os
import json
import uuid
from collections import Counter
import chromadb
from chromadb.utils import embedding_functions
from dotenv import load_dotenv

# ══════════════════════════════════════════════════════════════════════════════
# CONFIG
# ══════════════════════════════════════════════════════════════════════════════
load_dotenv()
os.environ["ANONYMIZED_TELEMETRY"] = "False"

DATA_DIR   = "data"
DB_PATH    = "./chroma_db"
COLLECTION = "residence_rules"
MODEL_NAME = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"

print("=" * 60)
print("  SYNDIC IA — Ingestion Base de Connaissances RAG (multi-JSON)")
print("=" * 60)


# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 — Lecture de tous les fichiers JSON dans data/
# ══════════════════════════════════════════════════════════════════════════════
print(f"\n📂 Étape 1 : Lecture des fichiers JSON dans '{DATA_DIR}/'...")

if not os.path.isdir(DATA_DIR):
    print(f"❌ Dossier introuvable : {DATA_DIR}/")
    exit(1)

json_files = sorted([f for f in os.listdir(DATA_DIR) if f.endswith(".json")])
if not json_files:
    print(f"❌ Aucun fichier .json trouvé dans {DATA_DIR}/")
    exit(1)

print(f"   📄 Fichiers trouvés : {json_files}")

# ── Chargement de tous les documents ──────────────────────────────────────────
all_documents = []   

for filename in json_files:
    filepath = os.path.join(DATA_DIR, filename)
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)

        source   = data.get("source", filename.replace(".json", ""))
        docs     = data.get("documents", [])
        category_hint = data.get("category_hint", "general")

        loaded = 0
        for doc in docs:
            doc_id   = doc.get("id") or str(uuid.uuid4())
            content  = doc.get("content", "").strip()
            title    = doc.get("title", "")
            category = doc.get("category", category_hint)
            urgency  = doc.get("urgency", "P3")

            if not content:
                print(f"   ⚠️  Document '{doc_id}' vide dans {filename} — ignoré")
                continue

            all_documents.append({
                "id":       f"{source}_{doc_id}",
                "content":  content,
                "title":    title,
                "category": category,
                "urgency":  urgency,
                "source":   source,
            })
            loaded += 1

        print(f"   ✅ {filename} → {loaded} documents chargés (source: '{source}')")

    except json.JSONDecodeError as e:
        print(f"   ❌ Erreur JSON dans {filename}: {e} — ignoré")
    except Exception as e:
        print(f"   ❌ Erreur lecture {filename}: {e} — ignoré")

print(f"\n   📊 Total : {len(all_documents)} documents chargés depuis {len(json_files)} fichiers")


# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 — Enrichissement : préfixe metadata dans le texte
# ══════════════════════════════════════════════════════════════════════════════
print("\n🔧 Étape 2 : Enrichissement des documents (préfixe metadata)...")

enriched_documents = []
metadatas          = []
doc_ids            = []

for doc in all_documents:
    prefix   = f"[URGENCE:{doc['urgency']} | CATÉGORIE:{doc['category']}]\n"
    if doc["title"]:
        prefix += f"Titre: {doc['title']}\n"
    enriched = prefix + doc["content"]

    enriched_documents.append(enriched)
    metadatas.append({
        "source":   doc["source"],
        "urgency":  doc["urgency"],
        "category": doc["category"],
        "title":    doc["title"],
    })
    doc_ids.append(doc["id"])

print(f"   ✅ {len(enriched_documents)} documents enrichis")
if enriched_documents:
    example = enriched_documents[0][:120].replace("\n", " ")
    print(f"   Exemple : '{example}...'")


# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 — Stats de répartition
# ══════════════════════════════════════════════════════════════════════════════
urgency_counts  = Counter(m["urgency"]  for m in metadatas)
category_counts = Counter(m["category"] for m in metadatas)
source_counts   = Counter(m["source"]   for m in metadatas)

print(f"\n📊 Étape 3 : Répartition des documents")
print(f"   Sources    : {dict(source_counts)}")
print(f"   Urgences   : {dict(urgency_counts)}")
print(f"   Catégories : {dict(category_counts)}")


# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 — Connexion ChromaDB + recréation de la collection
# ══════════════════════════════════════════════════════════════════════════════
print("\n🗄️  Étape 4 : Connexion ChromaDB...")

client         = chromadb.PersistentClient(path=DB_PATH)
embedding_func = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name=MODEL_NAME
)

try:
    client.delete_collection(name=COLLECTION)
    print(f"   🗑️  Ancienne collection '{COLLECTION}' supprimée")
except Exception:
    print(f"   ℹ️  Pas d'ancienne collection à supprimer")

collection = client.create_collection(
    name=COLLECTION,
    embedding_function=embedding_func,
    metadata={"hnsw:space": "cosine"},
)
print(f"   ✅ Collection '{COLLECTION}' créée (distance cosinus)")


# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 5 — Insertion par lots
# ══════════════════════════════════════════════════════════════════════════════
print("\n⬆️  Étape 5 : Vectorisation et insertion...")

BATCH_SIZE     = 10
total_inserted = 0

for batch_start in range(0, len(enriched_documents), BATCH_SIZE):
    batch_end  = min(batch_start + BATCH_SIZE, len(enriched_documents))
    collection.add(
        ids       = doc_ids[batch_start:batch_end],
        documents = enriched_documents[batch_start:batch_end],
        metadatas = metadatas[batch_start:batch_end],
    )
    total_inserted += batch_end - batch_start
    print(f"   📦 Batch {batch_start // BATCH_SIZE + 1} → {total_inserted}/{len(enriched_documents)} documents insérés")


# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 6 — Vérification par requêtes test
# ══════════════════════════════════════════════════════════════════════════════
print("\n🔍 Étape 6 : Vérification par requêtes test (top-3)...")
print("   Format : query → mots-clés attendus | urgence | catégorie\n")

# (query, mots_clés_attendus, urgence_attendue, catégorie_attendue)
test_cases = [
    (
        "odeur de gaz dans mon appartement que faire",
        ["gaz", "GAZ", "robinet", "évacuez", "ÉVACUEZ", "150"],
        "P0", "securite"
    ),
    (
        "ascenseur bloqué en panne personne coincée dedans",
        ["ascenseur", "OTIS", "alarme", "bloqué"],
        "P0", "ascenseur"
    ),
    (
        "bruit musique voisin la nuit impossible dormir",
        ["bruit", "BRUIT", "22h", "tapage", "voisin"],
        "P2", "nuisances"
    ),
    (
        "demande attestation residence document officiel",
        ["attestation", "24h", "document", "PDF"],
        "P3", "administratif"
    ),
    (
        "fuite eau robinet salle de bain appartement",
        ["fuite", "plombier", "robinet", "Youssef"],
        "P2", "plomberie"
    ),
    (
        "panne électricité tout l immeuble dans le noir",
        ["électri", "panne", "REDAL", "Hassan"],
        "P1", "electricite"
    ),
    (
        "comment payer les charges de copropriété",
        ["charges", "virement", "5", "mois"],
        "P3", "administratif"
    ),
    (
        "numéro urgence pompiers protection civile",
        ["150", "Protection Civile", "urgence"],
        "P0", "contacts"
    ),
]

all_ok = True
for query, expected_keywords, expected_urgency, expected_category in test_cases:
    results = collection.query(query_texts=[query], n_results=3)

    if not results["documents"] or not results["documents"][0]:
        print(f"   [❌❌❌] '{query[:50]}' — aucun résultat")
        all_ok = False
        continue

    found_keyword  = False
    found_urgency  = False
    found_category = False

    for doc, meta in zip(results["documents"][0], results["metadatas"][0]):
        combined = doc.upper() + str(meta).upper()
        if any(kw.upper() in combined for kw in expected_keywords):
            found_keyword = True
        if meta.get("urgency")  == expected_urgency:
            found_urgency = True
        if meta.get("category") == expected_category:
            found_category = True

    icon_kw  = "✅" if found_keyword  else "⚠️ "
    icon_urg = "✅" if found_urgency  else "⚠️ "
    icon_cat = "✅" if found_category else "⚠️ "

    top1_meta = results["metadatas"][0][0]
    top1_doc  = results["documents"][0][0][:70].replace("\n", " ")

    print(f"   [{icon_kw}{icon_urg}{icon_cat}] '{query[:50]}'")
    print(f"         Contenu:{icon_kw} | Urgence:{icon_urg}(attendu {expected_urgency}) | Catégorie:{icon_cat}(attendu {expected_category})")
    print(f"         Top-1 → urgency={top1_meta.get('urgency')} / category={top1_meta.get('category')} / source={top1_meta.get('source')}")
    print(f"         Top-1 doc → '{top1_doc}...'")

    if not (found_keyword and found_urgency and found_category):
        all_ok = False
    print()


# ══════════════════════════════════════════════════════════════════════════════
# RAPPORT FINAL
# ══════════════════════════════════════════════════════════════════════════════
print("=" * 60)
final_count = collection.count()
print(f"  ✅ Base vectorielle prête : {final_count} documents")
print(f"  📁 Stockée dans          : {os.path.abspath(DB_PATH)}")
print(f"  🏷️  Collection            : {COLLECTION}")
print(f"  🤖 Modèle                : {MODEL_NAME}")
print(f"  📂 Sources ingérées      : {list(source_counts.keys())}")
print(f"  🔧 Enrichissement        : Préfixe [URGENCE|CATÉGORIE] activé")
if all_ok:
    print(f"  🎯 Tests RAG             : TOUS RÉUSSIS ✅")
else:
    print(f"  ⚠️  Tests RAG             : CERTAINS ÉCHECS — voir détails ci-dessus")
print("=" * 60)

