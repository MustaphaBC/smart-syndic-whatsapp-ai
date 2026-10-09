# Script de soutenance — Smart Syndic IA
### Version finale · ~15–17 minutes · simple, sans répétition

> **Convention :** chaque bloc = une slide. Les *(indications)* en italique ne se lisent pas.

---

## [SLIDE 1 — Animation d'intro]
*(Attendre que la slide s'affiche, saluer le jury)*

---

## [SLIDE 2 — Page de titre]

Bonjour à tous.

Je m'appelle Mustapha Ben-Cheikh. Je vais vous présenter mon projet de fin d'études intitulé **Smart Syndic** — une plateforme intelligente de gestion des réclamations résidentielles via WhatsApp, IA générative et RAG — réalisé sous la direction du Professeur El Far Mohamed et du Professeur El Fahssi Khalid.

---

## [SLIDE 3 — Plan]

Ma présentation s'organise en **six parties** : le contexte, la solution, le cœur technique, les interfaces, le pilotage et enfin le bilan. Je vais avancer de façon progressive, du problème jusqu'à la démonstration.

---

## [SLIDE 4 — Divider Partie 1]
*(transition)*

---

## [SLIDE 5 — Contexte]

La gestion d'une résidence, c'est une communication permanente entre quatre profils : **les résidents** qui signalent leurs problèmes, **le syndic** qui les traite, **les administrateurs** qui valident les cas sensibles, et **les responsables** qui pilotent.

Pour que ça fonctionne bien, trois choses sont nécessaires : centraliser, prioriser, automatiser. Aujourd'hui, aucune de ces trois conditions n'est réellement remplie.

---

## [SLIDE 6 — Problématique]

Concrètement, j'ai identifié cinq problèmes récurrents dans le fonctionnement classique d'un syndic.

Les réclamations arrivent de partout — appels, WhatsApp, visites — sans aucune centralisation. 
Le suivi est manuel, donc des informations se perdent. 
Les urgences ne sont pas priorisées : une fuite de gaz peut rester en attente comme une simple question administrative. 
Il n'y a pas d'historique exploitable. 
Et il n'existe aucun outil de mesure — ni volumes, ni délais, ni satisfaction.

---

## [SLIDE 7 — Objectifs]

Face à ça, mon projet vise six objectifs précis.

Recevoir les réclamations automatiquement via WhatsApp. 
Identifier le résident depuis son numéro de téléphone. 
Classifier chaque demande — catégorie, sentiment, action requise.
 Détecter les urgences selon une échelle de P0 à P3. 
Centraliser tout le suivi dans un historique unique. 
Et donner à l'administrateur les outils pour valider rapidement et piloter son activité.

---

## [SLIDE 8 — Divider Partie 2]
*(transition)*

---

## [SLIDE 9 — Solution]

La réponse que j'apporte tient en une phrase : **WhatsApp comme canal d'entrée, l'IA comme cerveau, Flutter comme tour de contrôle.**

Le résident utilise WhatsApp — un canal qu'il connaît déjà, donc zéro friction. 
Le backend orchestre l'intelligence artificielle pour comprendre et traiter le message.
 Et l'administrateur pilote tout depuis un dashboard mobile.

---

## [SLIDE 10 — Architecture]

*(pointer le schéma)*

Voici comment les composants s'enchaînent. Le message WhatsApp passe par **Twilio**, arrive dans mon **backend FastAPI**,
 qui fait appel à trois services : **Groq** pour l'IA, **ChromaDB** pour le RAG, et **PostgreSQL** pour stocker les données. 
**Firebase** gère l'authentification et les notifications push. Le tout alimente en temps réel le **dashboard Flutter** de l'administrateur.

---

## [SLIDE 11 — Stack technique]

Côté technologies : le backend est en **Python / FastAPI** pour ses performances asynchrones. 
La base de données est **PostgreSQL** avec asyncpg, complétée par **Redis** pour le rate limiting. 
L'IA repose sur **Groq** — LLM Llama 3.3-70b, Whisper pour l'audio, et un modèle de vision pour les images. 
**ChromaDB** stocke la base vectorielle. Le frontend est en **Flutter**, et l'authentification ainsi que les alertes passent par **Firebase**.

---

## [SLIDE 12 — Divider Partie 3]
*(transition)*

---

## [SLIDE 13 — Backend main.py]

Le cœur du système, c'est le fichier `main.py`. Il expose **25 routes API REST** plus un canal **WebSocket**, tous consommés par le dashboard Flutter. 
Il héberge le webhook WhatsApp avec validation de signature Twilio, un pool asyncpg de 5 à 20 connexions, l'orchestration de Groq et ChromaDB, 
et les notifications Firebase vers le topic `admin_alerts`.

---

## [SLIDE 14 — Pipeline en 9 étapes]

*(pointer chaque étape)*

Voici le pipeline complet, en neuf étapes, qui transforme un message WhatsApp brut en ticket.

**1** — Réception via le webhook Twilio.
**2** — Validation de la signature HMAC pour s'assurer que la requête est légitime. 
**3** — Identification du résident depuis les neuf derniers chiffres de son numéro. 
**4** — Traitement du média : transcription Whisper si audio, analyse vision si image. 
**5** — Détection de la langue. 
**6** — Scan des mots-clés de sécurité critique. 
**7** — Récupération du contexte RAG depuis ChromaDB. 
**8** — Génération de la classification JSON par le LLM Groq. 
**9** — Création du ticket et décision : réponse automatique ou mise en attente de validation humaine.

Ce pipeline est entièrement **automatisé**, sans aucune intervention manuelle.

---

## [SLIDE 15 — Flux de traitement]

Je zoome sur trois mécanismes clés de ce pipeline.

La **détection de langue** fonctionne en trois couches : détection du script arabe par regex Unicode, 
                                                        reconnaissance de tokens darija romanisée — j'ai constitué un lexique de près de 50 expressions marocaines 
                                                        et en dernier recours langdetect. La réponse est ensuite générée dans la langue du résident.

La **classification IA** produit un JSON structuré : niveau d'urgence P0 à P3, catégorie, sentiment, et action requise.

La **gestion des urgences** repose sur un double mécanisme : le LLM classe, mais des mots-clés déterministes — gaz, incendie, ascenseur bloqué — 
        peuvent **forcer** la classification P0, indépendamment du modèle, et déclencher immédiatement une validation humaine et une alerte FCM.

---

## [SLIDE 16 — Cycle de vie d'une réclamation]

Chaque ticket suit six étapes : création, classification IA, attribution d'une priorité, validation humaine si nécessaire, envoi de la réponse WhatsApp

L'échelle de priorité est le cœur du système : **P0** pour le critique — gaz, incendie, ascenseur bloqué — SLA de 5 minutes. 
                                               **P1** pour l'urgent — fuite majeure, panne électrique — 30 minutes. 
                                               **P2** pour l'important — 4 heures. 
                                               **P3** pour l'administratif standard — 24 heures.

---

## [SLIDE 17 — Modèle de données]

La base de données comprend quatre tables. La table **tickets** est la centrale — elle stocke le texte, la langue, la catégorie, l'urgence, la réponse IA, 
le statut et la satisfaction. Les tables **résidences** et **résidents** forment le référentiel. Et **invite_codes** sécurise l'onboarding des administrateurs 
par code à usage unique. Tout est indexé sur le hash de contenu, le numéro de téléphone et le statut.

---

## [SLIDE 18 — RAG avec ChromaDB]

Le RAG est ce qui permet à l'IA de répondre avec les règles **spécifiques** de la résidence, et non des règles génériques.

Le script `ingest.py` vectorise les documents — règlement, procédures, contacts, FAQ — et les stocke dans ChromaDB. 
À chaque réclamation, le système récupère les chunks les plus pertinents par similarité cosinus, et les injecte dans le prompt envoyé au LLM. 
Résultat : une réponse ancrée dans le contexte métier réel, qui évite les hallucinations.

---

## [SLIDE 19 — IA multimodale]

L'IA du système n'est pas limitée au texte. Elle est **multimodale** sur trois canaux : le texte, bien sûr ; 
l'audio, transcrit par Whisper large-v3 directement dans le flux standard ; 
et l'image, analysée par un modèle de vision pour décrire visuellement le problème signalé. 
Et sur quatre langues : français, anglais, arabe, et darija marocaine romanisée.

---

## [SLIDE 20 — Agent Facebook]

En complément du cœur du système, j'ai développé un **agent autonome** de publication immobilière sur Facebook. 
Il détecte les unités vacantes en croisant PostgreSQL et un catalogue JSON, génère un visuel Pillow, 
rédige l'annonce avec le LLM en français et arabe marocain mixte, publie sur la page Facebook via l'API Graph, 
partage dans des groupes via Playwright, et évite les doublons grâce à un tracker JSON sur 48 heures.

---

## [SLIDE 21 — Divider Partie 4]
*(transition)*

---

## [SLIDE 22 — Dashboard Flutter]

Le dashboard est l'interface quotidienne de l'administrateur. Il comprend **sept écrans** : 
connexion, gestion des résidences, gestion des résidents, grille de tickets en temps réel, historique, analytics, et compte personnel.

---

## [SLIDE 23 — Détails frontend]

Chaque écran a un rôle précis. La connexion utilise Firebase Auth avec un code d'invitation à usage unique. 
La grille affiche les tickets pending et se met à jour via WebSocket. 
La gestion des résidents inclut un broadcast WhatsApp pour diffuser un message à toute une résidence. 
L'historique et les analytics exposent les KPIs, les catégories et la satisfaction. 
Et les notifications FCM remontent les alertes P0 et P1 directement sur l'appareil mobile.

---

## [SLIDE 24 — Temps réel]

Deux mécanismes assurent le temps réel. **Firebase Cloud Messaging** : dès qu'une urgence est détectée, une notification est poussée sur le topic `admin_alerts`. 
                             **WebSocket** : à chaque nouveau ticket, le backend diffuse un message `REFRESH`, et le dashboard Flutter recharge automatiquement.

Concrètement : une urgence arrive à l'administrateur **en quelques secondes**, sans aucun rafraîchissement manuel.

---

## [SLIDE 25 — Divider Partie 5]
*(transition)*

---

## [SLIDE 26 — KPIs]

Sur mon jeu de données de démonstration : **536 tickets** traités, taux de résolution **100%**, **112 urgences P0 et P1** — 
et la totalité de ces urgences est bien passée par une validation humaine. 
Le dashboard suit également le respect du SLA par niveau et les catégories les plus fréquentes.

---

## [SLIDE 27 — Tests & Validation]

La validation repose sur quatre niveaux. 
Les 8 tests RAG intégrés dans `ingest.py` sont **tous réussis**.
Les 12 scénarios WhatsApp — toutes langues et types de médias — sont **tous validés**. 
Les 7 tests de sécurité — HMAC, JWT, CORS — sont validés. 
Et les garde-fous P0 n'ont produit **aucun faux négatif** sur les mots-clés critiques.

Côté qualité IA : 100% des réponses sont des JSON parsables, cohérence catégorie-urgence supérieure à 90%, et réponse dans la bonne langue dans 95% des cas.

---

## [SLIDE 28 — Sécurité]

Les mécanismes de sécurité en place : vérification de signature Twilio sur le webhook, authentification Firebase JWT pour les administrateurs, 
secrets gérés exclusivement par variables d'environnement, rate limiting Redis en mode dégradé gracieux.
Ce qui reste à renforcer avant production : un système de rôles multi-niveaux, l'authentification du canal WebSocket, 
une rotation régulière des clés API, et un audit des opérations administrateur.

---

## [SLIDE 29 — Divider Partie 6]
*(transition)*

---

## [SLIDE 30 — Points forts]

Je retiens huit points forts : un workflow complet de bout en bout, une IA multimodale texte-audio-image, le support natif de la darija, WhatsApp comme canal sans friction, le RAG qui ancre les réponses dans le métier réel, un dashboard Flutter multiplateforme, des alertes doublement sécurisées par FCM et WebSocket, et des analytics intégrés dès la conception.

---

## [SLIDE 31 — Limites & roadmap]

En toute honnêteté, voici les limites actuelles : le backend est monolithique — `main.py` concentre environ 1 000 lignes, ce qui crée un fort couplage. Il manque une suite de tests automatisés backend. Le déploiement est local via ngrok, sans Docker ni CI/CD. Et le canal WebSocket n'est pas authentifié.

La feuille de route est claire : conteneurisation Docker, CI/CD, RBAC granulaire, architecture modulaire, monitoring de latence LLM, et évolution vers un **SaaS multi-résidences**.

---

## [SLIDE 32 — Démo]

*(Lancer la démonstration live si disponible)*

Le scénario est simple : un résident envoie une réclamation WhatsApp, l'IA la classifie, un ticket est créé avec sa priorité, une alerte FCM est envoyée à l'administrateur, et l'admin traite depuis son dashboard — **aucune intervention manuelle entre les étapes.**

---

## [SLIDE 33 — Conclusion]

Pour conclure : Smart Syndic est un **MVP avancé et fonctionnel**, qui répond à une vraie problématique métier marocaine. L'architecture — FastAPI, IA, Flutter, cloud — est cohérente et conçue pour évoluer. La prochaine étape naturelle est de le transformer en **SaaS multi-résidences**, accessible à n'importe quel syndic.

Merci pour votre attention. Je suis à votre disposition pour les questions.

---

## [SLIDE 34 — Merci]

*(Attendre les questions, sourire, rester debout)*

---

---

# Questions probables du jury

**Q1. Pourquoi Groq et pas OpenAI ?**
Groq utilise des puces LPU qui offrent une latence très faible — critique pour des réponses WhatsApp quasi-instantanées. À coût équivalent, la vitesse était un avantage décisif pour ce projet.

**Q2. Comment un P0 ne peut-il jamais être raté ?**
Double mécanisme : le LLM classifie, mais des mots-clés déterministes — gaz, incendie, ascenseur — peuvent forcer P0 indépendamment du modèle. Même si le LLM se trompe, le mot-clé prime toujours.

**Q3. Que se passe-t-il si Groq ou Twilio tombe ?**
Dégradation gracieuse : si le LLM échoue après 3 tentatives avec backoff, un fallback P3 générique est retourné et le ticket reste tracé en base. Si Redis est absent, le rate limiting est simplement désactivé sans bloquer le service.

**Q4. Pourquoi PostgreSQL et pas du NoSQL ?**
Les données sont fortement relationnelles — tickets liés à des résidents, liés à des résidences — avec besoin de transactions et d'intégrité référentielle. PostgreSQL avec asyncpg donne ce niveau de garantie sans sacrifier la performance asynchrone.

**Q5. Le projet est-il en production ?**
Non, c'est un prototype fonctionnel validé sur un jeu de données de démonstration, déployé localement via ngrok. La feuille de route vers la production est définie : Docker, CI/CD, environnements staging/production séparés.

**Q6. Comment mesurez-vous la qualité des réponses IA ?**
Sur trois axes : validité structurelle du JSON, cohérence catégorie-urgence sur les cas non ambigus, et revue manuelle systématique pour tous les P0/P1 — puisque ceux-ci passent obligatoirement par validation humaine avant envoi.

**Q7. Quelle est la limite principale que vous changeriez en priorité ?**
La modularisation du backend. Concentrer toute la logique dans un seul fichier a permis d'itérer vite, mais avant toute mise en production, je découperais en couches séparées : routes, services, repositories, et schemas.
