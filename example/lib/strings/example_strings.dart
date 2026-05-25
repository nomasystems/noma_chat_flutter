/// Example-app strings (not part of the SDK). Mirrors the multi-locale
/// pattern of `ChatUiLocalizations`: every supported language has a
/// `static const` instance and `forLanguageCode` normalises an IETF
/// tag (e.g. `pt_BR`) to one of them.
///
/// Kept separate from the SDK so consumers of `noma_chat` don't have
/// to ship the example-only copy (onboarding form, suggestion bar,
/// language picker, error toast, etc.).
class ExampleStrings {
  const ExampleStrings({
    // Onboarding — header + mode picker.
    this.onboardingSubtitle = 'Configure the example to your liking',
    this.modeMock = 'Mock',
    this.modeReal = 'Real',

    // Onboarding — real-mode intro lines.
    this.realIntroBackend = 'Connects to a real backend.',
    this.realIntroMultiInstance =
        'You need several instances on different terminals.',

    // Onboarding — username field.
    this.usernameLabel = 'Your name',
    this.usernameHelper = 'At least 3 characters (e.g. "alice")',

    // Onboarding — backend section.
    this.backendTitle = 'Backend',
    this.baseUrlLabel = 'Base URL (REST)',
    this.wsUrlLabel = 'WS URL',
    this.sseUrlLabel = 'SSE URL',

    // Onboarding — advanced section.
    this.advancedTitle = 'Advanced',
    this.advRealtimeMode = 'Realtime mode',
    this.advRealtimeModeTip =
        'Auto: WS primary with SSE failover (recommended). '
        'WebSocket only: never falls back to SSE. '
        'SSE only: skip the WS handshake — works behind WS-blocking '
        'proxies. Polling: REST tick every N seconds, no stream. '
        'Manual: only refreshes on pull-to-refresh / chat.refresh().',
    this.advPollingInterval = 'Polling interval (s)',
    this.advPollingIntervalTip =
        'How often the polling engine ticks. Default 15 s; the SDK '
        'rejects anything below 5 s.',
    this.advPollUnreadOnly = 'Poll only unread rooms',
    this.advPollUnreadOnlyTip =
        'When ON the engine asks for rooms with unread messages only. '
        'OFF polls every room — heavier on the backend but catches '
        'silent edits.',
    this.advPollOpenRooms = 'Poll messages of open rooms',
    this.advPollOpenRoomsTip =
        'When ON each tick also pulls messages for rooms with an '
        'active ChatController (the open chat). Tradeoff: 1 extra '
        'request per tick per open chat.',
    this.refreshTooltip = 'Refresh',
    this.refreshDone = 'Refreshed',
    this.appModeSelectorTitle = 'Choose how to run the example',
    this.appModeSelectorIntro =
        'Pick a preset. You can switch later from the app overflow.',
    this.appModeDemoTitle = 'Demo',
    this.appModeDemoDescription =
        'No setup. Mock data + sample chats ready to poke. What the '
        'README "5 lines" demonstrates.',
    this.appModeBasicTitle = 'Basic',
    this.appModeBasicDescription =
        'Minimal onboarding: display name + optional real backend. '
        'Sensible defaults for typical integration.',
    this.appModeAdvancedTitle = 'Advanced (Lab)',
    this.appModeAdvancedDescription =
        'Every config knob the SDK exposes, grouped by realtime mode. '
        'Used by /observa-noma sessions.',
    this.basicOnboardingTitle = 'Basic setup',
    this.basicOnboardingIntro =
        'Real CHT backend with the minimum config you need. For mock '
        'data with no setup pick Demo from the selector; for every '
        'config knob the SDK exposes pick Advanced.',
    this.advSectionGlobal = 'Global',
    this.advSectionRealtime = 'Realtime',
    this.advSseIdleTimeout = 'SSE idle timeout (s)',
    this.advSseIdleTimeoutTip =
        'Reconnect SSE if no chunks arrive in this window. Default '
        '60 s. Set 0 to disable the watchdog (the SDK accepts null).',
    this.advPollMaxRoomsPerTick = 'Max rooms per tick',
    this.advPollMaxRoomsPerTickTip =
        'Cap on messages.list fan-out per polling tick. Default 10. '
        'Protects the backend when many rooms change at once.',
    this.advManualHint =
        'Manual mode has no background channel — updates only arrive '
        'when you tap the refresh button or pull-to-refresh.',
    this.advRequestTimeout = 'Request timeout (s)',
    this.advRequestTimeoutTip =
        'Per-call REST timeout in seconds. Default 30. Lower it to '
        'exercise retry / banner UX; raise it on flaky networks.',
    this.advWsReconnectDelay = 'WS reconnect delay (s)',
    this.advWsReconnectDelayTip =
        'Base delay between WebSocket reconnect attempts. The SDK '
        'applies exponential backoff on top of this. Default 2 — '
        'matches the CHT keepalive window so a transient kill drops '
        'reconnect within ~5s.',
    this.advMaxReconnect = 'Max reconnect attempts',
    this.advMaxReconnectTip =
        'How many times the SDK retries the WebSocket before giving '
        'up and surfacing a persistent disconnected state. Empty '
        '(default) = infinite — retries forever with backoff.',
    this.advEventBuffer = 'Event replay buffer',
    this.advEventBufferTip =
        'How many of the most recent realtime events the SDK keeps in '
        'memory to "replay" to a listener that subscribes a moment '
        'after connecting (so it does not miss events that arrived in '
        'that gap). Default 20 — fine for almost everyone. It does NOT '
        'recover events missed during a network outage: that is handled '
        'separately by reconnect resync (the SDK reloads rooms and '
        'messages when the connection comes back).',

    // Onboarding — demo-mode pitch.
    this.demoModeTitle = 'Demo mode',
    this.demoModeBodyTechnical =
        'Production-grade chat infrastructure for real apps. '
        'Real-time messaging, offline persistence, moderation tooling '
        'and a polished Flutter SDK — engineered, hosted and operated '
        'by Nomasystems at scale. You ship the product; we run the '
        'messaging.',
    this.demoModeBodyCommercial =
        'The full product is a turnkey chat backend by Nomasystems '
        'with an admin panel, moderation tools, broadcast rooms, '
        'a metrics dashboard, audit log, webhooks, and the rest '
        'of the operational surface — none of which ship in this '
        'demo.',
    this.demoModeRequestPrefix = 'Request a live demo at ',
    this.demoModeFeatureRealtime = 'Real-time messaging',
    this.demoModeFeatureOffline = 'Offline-first with persistent cache',
    this.demoModeFeatureAdmin = 'Admin panel, moderation, audit log',
    this.demoModeFeatureSdk = 'Flutter SDK ready to drop into your app',
    this.demoModeCtaLabel = 'Get in touch',

    // Onboarding — CTA.
    this.enterChat = 'Enter chat',

    // Home — search + overflow.
    this.openSearch = 'Search users',
    this.closeSearch = 'Close search',
    this.searchUsersHint = 'Search users by name (≥2 chars)',
    this.suggestionsTitle = 'Suggestions',
    this.languageMenu = 'Language',
    this.cancelSelection = 'Cancel selection',
    this.selectedCountTemplate = '{count} selected',
    this.acceptedInvitationTemplate = 'Accepted invitation to {name}',
    this.acceptedInvitationFallback = 'room',

    // Chat room.
    this.reportReasonHint = 'Report reason',

    // Global error banner.
    this.globalErrorTemplate = '{kind} failed: {failure}',

    // Room-removed snackbars (kicked / banned / left).
    this.bannedFromRoom = 'You were banned from this room',
    this.bannedFromRoomWithReasonTemplate =
        'You were banned from this room: {reason}',
    this.leftRoomWithReasonTemplate = 'You left this room: {reason}',
    this.leftRoomReasonTemplate = 'You left this room ({reason})',

    // Other home-page operation errors.
    this.failedToOpenRoomTemplate = 'Failed to open room: {error}',
  });

  final String onboardingSubtitle;
  final String modeMock;
  final String modeReal;

  final String realIntroBackend;
  final String realIntroMultiInstance;

  final String usernameLabel;
  final String usernameHelper;

  final String backendTitle;
  final String baseUrlLabel;
  final String wsUrlLabel;
  final String sseUrlLabel;

  final String advancedTitle;
  final String advRealtimeMode;
  final String advRealtimeModeTip;
  final String advPollingInterval;
  final String advPollingIntervalTip;
  final String advPollUnreadOnly;
  final String advPollUnreadOnlyTip;
  final String advPollOpenRooms;
  final String advPollOpenRoomsTip;
  final String refreshTooltip;
  final String refreshDone;
  final String appModeSelectorTitle;
  final String appModeSelectorIntro;
  final String appModeDemoTitle;
  final String appModeDemoDescription;
  final String appModeBasicTitle;
  final String appModeBasicDescription;
  final String appModeAdvancedTitle;
  final String appModeAdvancedDescription;
  final String basicOnboardingTitle;
  final String basicOnboardingIntro;
  final String advSectionGlobal;
  final String advSectionRealtime;
  final String advSseIdleTimeout;
  final String advSseIdleTimeoutTip;
  final String advPollMaxRoomsPerTick;
  final String advPollMaxRoomsPerTickTip;
  final String advManualHint;
  final String advRequestTimeout;
  final String advRequestTimeoutTip;
  final String advWsReconnectDelay;
  final String advWsReconnectDelayTip;
  final String advMaxReconnect;
  final String advMaxReconnectTip;
  final String advEventBuffer;
  final String advEventBufferTip;

  final String demoModeTitle;
  final String demoModeBodyTechnical;
  final String demoModeBodyCommercial;
  final String demoModeRequestPrefix;
  final String demoModeFeatureRealtime;
  final String demoModeFeatureOffline;
  final String demoModeFeatureAdmin;
  final String demoModeFeatureSdk;
  final String demoModeCtaLabel;

  final String enterChat;

  final String openSearch;
  final String closeSearch;
  final String searchUsersHint;
  final String suggestionsTitle;
  final String languageMenu;
  final String cancelSelection;
  final String selectedCountTemplate;
  final String acceptedInvitationTemplate;
  final String acceptedInvitationFallback;

  final String reportReasonHint;

  final String globalErrorTemplate;

  final String bannedFromRoom;
  final String bannedFromRoomWithReasonTemplate;
  final String leftRoomWithReasonTemplate;
  final String leftRoomReasonTemplate;

  final String failedToOpenRoomTemplate;

  /// Languages we ship strings for. Same set as the SDK so the picker
  /// renders one entry per language for both the chat UI and the
  /// example surfaces — no mixed locales possible.
  static const List<String> supportedLanguageCodes = [
    'en',
    'es',
    'fr',
    'de',
    'it',
    'pt',
    'ca',
  ];

  /// Resolves an IETF tag (e.g. `pt_BR`, `pt-BR`, `pt`) to one of the
  /// shipped instances. Falls back to [en] when the primary subtag is
  /// not supported.
  static ExampleStrings forLanguageCode(String? code) {
    if (code == null || code.isEmpty) return en;
    final primary = code.split(RegExp(r'[-_]')).first.toLowerCase();
    return switch (primary) {
      'es' => es,
      'fr' => fr,
      'de' => de,
      'it' => it,
      'pt' => pt,
      'ca' => ca,
      _ => en,
    };
  }

  static const ExampleStrings en = ExampleStrings();

  static const ExampleStrings es = ExampleStrings(
    onboardingSubtitle: 'Configura el ejemplo a tu gusto',
    modeMock: 'Mock',
    modeReal: 'Real',
    realIntroBackend: 'Se conecta a un backend real.',
    realIntroMultiInstance:
        'Necesitas varias instancias en distintos terminales.',
    usernameLabel: 'Tu nombre',
    usernameHelper: 'Al menos 3 caracteres (p. ej. "alice")',
    backendTitle: 'Backend',
    baseUrlLabel: 'URL base (REST)',
    wsUrlLabel: 'URL WS',
    sseUrlLabel: 'URL SSE',
    advancedTitle: 'Avanzado',
    advRealtimeMode: 'Modo en tiempo real',
    advRealtimeModeTip:
        'Auto: WS primario con failover a SSE (recomendado). '
        'Solo WebSocket: sin fallback. Solo SSE: salta el handshake '
        'WS — útil tras proxies que bloquean WS. Polling: tick REST '
        'cada N segundos. Manual: solo refresca con pull-to-refresh '
        'o chat.refresh().',
    advPollingInterval: 'Intervalo de polling (s)',
    advPollingIntervalTip:
        'Cada cuánto el motor de polling hace tick. Por defecto 15 s; '
        'el SDK rechaza valores < 5 s.',
    advPollUnreadOnly: 'Solo rooms con no leídos',
    advPollUnreadOnlyTip:
        'Si ON pregunta solo por rooms con mensajes no leídos. OFF '
        'consulta todos los rooms — más carga al backend pero captura '
        'ediciones silenciosas.',
    advPollOpenRooms: 'Sondear mensajes de chats abiertos',
    advPollOpenRoomsTip:
        'Si ON cada tick también extrae mensajes de rooms con un '
        'ChatController activo. Trade-off: 1 request extra por tick '
        'por chat abierto.',
    refreshTooltip: 'Actualizar',
    refreshDone: 'Actualizado',
    appModeSelectorTitle: 'Elige cómo ejecutar el example',
    appModeSelectorIntro:
        'Selecciona un preset. Puedes cambiarlo después desde el menú de la app.',
    appModeDemoTitle: 'Demo',
    appModeDemoDescription:
        'Sin configuración. Datos mock + chats de ejemplo listos para '
        'explorar. Lo que demuestran las "5 líneas" del README.',
    appModeBasicTitle: 'Básico',
    appModeBasicDescription:
        'Onboarding mínimo: nombre + backend real opcional. Defaults '
        'razonables para una integración típica.',
    appModeAdvancedTitle: 'Avanzado (Lab)',
    appModeAdvancedDescription:
        'Todos los toggles del SDK, agrupados por modo en tiempo real. '
        'Usado por las sesiones /observa-noma.',
    basicOnboardingTitle: 'Configuración básica',
    basicOnboardingIntro:
        'Backend CHT real con la configuración mínima. Para datos mock '
        'sin setup elige Demo desde el selector; para todos los toggles '
        'del SDK, Avanzado.',
    advSectionGlobal: 'Global',
    advSectionRealtime: 'Tiempo real',
    advSseIdleTimeout: 'Timeout idle SSE (s)',
    advSseIdleTimeoutTip:
        'Reconecta SSE si no llegan chunks en este intervalo. Por '
        'defecto 60 s. 0 desactiva el watchdog (el SDK acepta null).',
    advPollMaxRoomsPerTick: 'Máx rooms por tick',
    advPollMaxRoomsPerTickTip:
        'Tope de messages.list por tick de polling. Por defecto 10. '
        'Protege el backend cuando muchos rooms cambian a la vez.',
    advManualHint:
        'El modo manual no tiene canal en background — las '
        'actualizaciones solo llegan al tocar refresh o pull-to-refresh.',
    advRequestTimeout: 'Timeout de petición (s)',
    advRequestTimeoutTip:
        'Timeout REST por llamada en segundos. Por defecto 30. Bájalo '
        'para ejercitar reintentos / UX de banner; súbelo en redes '
        'inestables.',
    advWsReconnectDelay: 'Retardo de reconexión WS (s)',
    advWsReconnectDelayTip:
        'Retardo base entre intentos de reconexión del WebSocket. El SDK '
        'aplica backoff exponencial por encima. Por defecto 2 — encaja con '
        'la ventana de keepalive de CHT, así una caída transitoria '
        'reconecta en ~5s.',
    advMaxReconnect: 'Reintentos máximos de reconexión',
    advMaxReconnectTip:
        'Cuántas veces reintenta el SDK el WebSocket antes de rendirse y '
        'exponer un estado desconectado persistente. Vacío (por defecto) = '
        'infinito — reintenta para siempre con backoff.',
    advEventBuffer: 'Buffer de repetición de eventos',
    advEventBufferTip:
        'Cuántos eventos recientes guarda el SDK en memoria para '
        '"repetírselos" a un listener que se suscribe un instante '
        'después de conectar (así no se pierde los eventos que llegaron '
        'en ese hueco). Por defecto 20 — suficiente para casi todos. NO '
        'recupera eventos perdidos durante un corte de red: eso lo '
        'resuelve aparte el resync al reconectar (el SDK recarga salas y '
        'mensajes cuando vuelve la conexión).',
    demoModeTitle: 'Modo demo',
    demoModeBodyTechnical:
        'Infraestructura de chat de producción para apps reales. '
        'Mensajería en tiempo real, persistencia offline, herramientas '
        'de moderación y un SDK de Flutter pulido — diseñado, alojado '
        'y operado por Nomasystems a escala. Tú lanzas el producto; '
        'nosotros llevamos la mensajería.',
    demoModeBodyCommercial:
        'El producto completo es un backend de chat llave en mano de '
        'Nomasystems con panel de administración, herramientas de '
        'moderación, salas broadcast, dashboard de métricas, audit log, '
        'webhooks y el resto de la superficie operativa — nada de eso '
        'viaja en este demo.',
    demoModeRequestPrefix: 'Solicita una demo en vivo en ',
    demoModeFeatureRealtime: 'Mensajería en tiempo real',
    demoModeFeatureOffline: 'Offline-first con caché persistente',
    demoModeFeatureAdmin: 'Panel admin, moderación, audit log',
    demoModeFeatureSdk: 'SDK Flutter listo para tu app',
    demoModeCtaLabel: 'Pide información',
    enterChat: 'Entrar al chat',
    openSearch: 'Buscar usuarios',
    closeSearch: 'Cerrar búsqueda',
    searchUsersHint: 'Busca usuarios por nombre (≥2 caracteres)',
    suggestionsTitle: 'Sugerencias',
    languageMenu: 'Idioma',
    cancelSelection: 'Cancelar selección',
    selectedCountTemplate: '{count} seleccionados',
    acceptedInvitationTemplate: 'Invitación aceptada a {name}',
    acceptedInvitationFallback: 'sala',
    reportReasonHint: 'Motivo del reporte',
    globalErrorTemplate: '{kind} ha fallado: {failure}',
    bannedFromRoom: 'Te han baneado de esta sala',
    bannedFromRoomWithReasonTemplate: 'Te han baneado de esta sala: {reason}',
    leftRoomWithReasonTemplate: 'Has salido de esta sala: {reason}',
    leftRoomReasonTemplate: 'Has salido de esta sala ({reason})',
    failedToOpenRoomTemplate: 'No se pudo abrir la sala: {error}',
  );

  static const ExampleStrings fr = ExampleStrings(
    onboardingSubtitle: 'Configurez l\'exemple à votre goût',
    modeMock: 'Mock',
    modeReal: 'Réel',
    realIntroBackend: 'Se connecte à un backend réel.',
    realIntroMultiInstance:
        'Tu as besoin de plusieurs instances sur différents terminaux.',
    usernameLabel: 'Votre nom',
    usernameHelper: 'Au moins 3 caractères (p. ex. « alice »)',
    backendTitle: 'Backend',
    baseUrlLabel: 'URL de base (REST)',
    wsUrlLabel: 'URL WS',
    sseUrlLabel: 'URL SSE',
    advancedTitle: 'Avancé',
    advRealtimeMode: 'Mode temps réel',
    advRealtimeModeTip:
        'Auto : WS primaire avec bascule SSE (recommandé). '
        'WebSocket uniquement : sans bascule. SSE uniquement : '
        'évite le handshake WS — utile derrière les proxys qui '
        'bloquent WS. Polling : tick REST toutes les N secondes. '
        'Manuel : rafraîchit uniquement avec pull-to-refresh ou '
        'chat.refresh().',
    advPollingInterval: 'Intervalle de polling (s)',
    advPollingIntervalTip:
        'Cadence du polling. Par défaut 15 s ; le SDK rejette toute '
        'valeur inférieure à 5 s.',
    advPollUnreadOnly: 'Polling rooms non lus seulement',
    advPollUnreadOnlyTip:
        'Si ON demande uniquement les rooms avec messages non lus. '
        'OFF interroge toutes les rooms — plus lourd côté backend '
        'mais détecte les éditions silencieuses.',
    advPollOpenRooms: 'Polling des messages des chats ouverts',
    advPollOpenRoomsTip:
        'Si ON chaque tick récupère aussi les messages des rooms '
        'avec un ChatController actif. Compromis : 1 requête '
        'supplémentaire par tick par chat ouvert.',
    refreshTooltip: 'Rafraîchir',
    refreshDone: 'Rafraîchi',
    appModeSelectorTitle: 'Choisis comment lancer l\'exemple',
    appModeSelectorIntro:
        'Sélectionne un preset. Tu peux changer plus tard depuis le menu.',
    appModeDemoTitle: 'Démo',
    appModeDemoDescription:
        'Aucune config. Données mock + chats d\'exemple prêts à tester. '
        'Ce que démontrent les "5 lignes" du README.',
    appModeBasicTitle: 'Basique',
    appModeBasicDescription:
        'Onboarding minimal : nom + backend réel optionnel. Defaults '
        'raisonnables pour une intégration typique.',
    appModeAdvancedTitle: 'Avancé (Lab)',
    appModeAdvancedDescription:
        'Tous les paramètres du SDK, groupés par mode temps réel. '
        'Utilisé par les sessions /observa-noma.',
    basicOnboardingTitle: 'Configuration basique',
    basicOnboardingIntro:
        'Backend CHT réel avec la config minimale. Pour données mock '
        'sans setup choisis Démo depuis le sélecteur ; pour toutes les '
        'options du SDK, Avancé.',
    advSectionGlobal: 'Global',
    advSectionRealtime: 'Temps réel',
    advSseIdleTimeout: 'Timeout idle SSE (s)',
    advSseIdleTimeoutTip:
        'Reconnecte SSE si aucun chunk n\'arrive dans cet intervalle. '
        'Par défaut 60 s. 0 désactive le watchdog.',
    advPollMaxRoomsPerTick: 'Max rooms par tick',
    advPollMaxRoomsPerTickTip:
        'Plafond messages.list par tick de polling. Par défaut 10. '
        'Protège le backend quand plusieurs rooms changent.',
    advManualHint:
        'Le mode manuel n\'a pas de canal en background — les mises '
        'à jour n\'arrivent qu\'au refresh / pull-to-refresh.',
    advRequestTimeout: 'Délai de requête (s)',
    advRequestTimeoutTip:
        'Délai REST par appel en secondes. Par défaut 30. Baissez-le '
        'pour exercer le retry / l\'UX de bannière ; augmentez-le sur '
        'réseaux instables.',
    advWsReconnectDelay: 'Délai de reconnexion WS (s)',
    advWsReconnectDelayTip:
        'Délai de base entre les tentatives de reconnexion du WebSocket. Le '
        'SDK applique un backoff exponentiel par-dessus. Par défaut 2 — '
        'correspond à la fenêtre keepalive de CHT, donc une coupure '
        'transitoire reconnecte en ~5s.',
    advMaxReconnect: 'Tentatives de reconnexion max.',
    advMaxReconnectTip:
        'Combien de fois le SDK retente le WebSocket avant d\'abandonner et '
        'd\'exposer un état déconnecté persistant. Vide (par défaut) = '
        'infini — retente toujours avec backoff.',
    advEventBuffer: 'Taille du buffer d\'événements',
    advEventBufferTip:
        'Nombre maximum d\'événements temps réel mis en mémoire tampon '
        'pendant que l\'app n\'est pas abonnée (p. ex. en arrière-plan). '
        'Par défaut 0 — sans buffer, le SDK élimine les événements plus '
        'anciens que la dernière synchro. Montez à 100+ pour un replay '
        'plus riche à la reprise.',
    demoModeTitle: 'Mode démo',
    demoModeBodyTechnical:
        'Infrastructure de chat de production pour vraies apps. '
        'Messagerie temps réel, persistance offline, outils de '
        'modération et un SDK Flutter soigné — conçu, hébergé et '
        'opéré par Nomasystems à l\'échelle. Tu livres le produit ; '
        'nous faisons tourner la messagerie.',
    demoModeBodyCommercial:
        'Le produit complet est un backend de chat clé en main par '
        'Nomasystems avec panneau d\'administration, outils de modération, '
        'salons broadcast, tableau de bord de métriques, audit log, '
        'webhooks et le reste de la surface opérationnelle — rien de tout '
        'cela n\'est inclus dans cette démo.',
    demoModeRequestPrefix: 'Demandez une démo en direct à ',
    demoModeFeatureRealtime: 'Messagerie temps réel',
    demoModeFeatureOffline: 'Offline-first avec cache persistant',
    demoModeFeatureAdmin: 'Panel admin, modération, audit log',
    demoModeFeatureSdk: 'SDK Flutter prêt pour ton app',
    demoModeCtaLabel: 'Nous contacter',
    enterChat: 'Entrer dans le chat',
    openSearch: 'Rechercher des utilisateurs',
    closeSearch: 'Fermer la recherche',
    searchUsersHint: 'Rechercher des utilisateurs par nom (≥2 caractères)',
    suggestionsTitle: 'Suggestions',
    languageMenu: 'Langue',
    cancelSelection: 'Annuler la sélection',
    selectedCountTemplate: '{count} sélectionnés',
    acceptedInvitationTemplate: 'Invitation à {name} acceptée',
    acceptedInvitationFallback: 'salon',
    reportReasonHint: 'Motif du signalement',
    globalErrorTemplate: '{kind} a échoué : {failure}',
    bannedFromRoom: 'Vous avez été banni de ce salon',
    bannedFromRoomWithReasonTemplate:
        'Vous avez été banni de ce salon : {reason}',
    leftRoomWithReasonTemplate: 'Vous avez quitté ce salon : {reason}',
    leftRoomReasonTemplate: 'Vous avez quitté ce salon ({reason})',
    failedToOpenRoomTemplate: 'Impossible d\'ouvrir le salon : {error}',
  );

  static const ExampleStrings de = ExampleStrings(
    onboardingSubtitle: 'Konfiguriere das Beispiel nach deinem Geschmack',
    modeMock: 'Mock',
    modeReal: 'Echt',
    realIntroBackend: 'Verbindet sich mit einem echten Backend.',
    realIntroMultiInstance:
        'Du brauchst mehrere Instanzen auf verschiedenen Endgeräten.',
    usernameLabel: 'Dein Name',
    usernameHelper: 'Mindestens 3 Zeichen (z. B. „alice")',
    backendTitle: 'Backend',
    baseUrlLabel: 'Basis-URL (REST)',
    wsUrlLabel: 'WS-URL',
    sseUrlLabel: 'SSE-URL',
    advancedTitle: 'Erweitert',
    advRealtimeMode: 'Echtzeitmodus',
    advRealtimeModeTip:
        'Auto: WS primär mit SSE-Failover (empfohlen). '
        'Nur WebSocket: kein Failover. Nur SSE: WS-Handshake '
        'wird übersprungen — nützlich hinter Proxys, die WS '
        'blockieren. Polling: REST-Tick alle N Sekunden. '
        'Manuell: nur via Pull-to-Refresh oder chat.refresh().',
    advPollingInterval: 'Polling-Intervall (s)',
    advPollingIntervalTip:
        'Wie oft die Polling-Engine tickt. Standard 15 s; das SDK '
        'lehnt Werte unter 5 s ab.',
    advPollUnreadOnly: 'Nur ungelesene Räume pollen',
    advPollUnreadOnlyTip:
        'Wenn AN werden nur Räume mit ungelesenen Nachrichten '
        'abgefragt. AUS fragt alle Räume ab — höhere Backend-Last, '
        'erfasst stille Bearbeitungen.',
    advPollOpenRooms: 'Nachrichten offener Räume pollen',
    advPollOpenRoomsTip:
        'Wenn AN holt jeder Tick zusätzlich Nachrichten für Räume '
        'mit aktivem ChatController. Trade-off: 1 zusätzliche '
        'Anfrage pro Tick pro offenem Chat.',
    refreshTooltip: 'Aktualisieren',
    refreshDone: 'Aktualisiert',
    appModeSelectorTitle: 'Wähle, wie das Beispiel laufen soll',
    appModeSelectorIntro:
        'Wähle ein Preset. Du kannst es später im App-Menü ändern.',
    appModeDemoTitle: 'Demo',
    appModeDemoDescription:
        'Keine Konfiguration. Mock-Daten + Beispiel-Chats zum Stöbern. '
        'Was die "5 Zeilen" der README zeigen.',
    appModeBasicTitle: 'Basis',
    appModeBasicDescription:
        'Minimales Onboarding: Name + optionales echtes Backend. '
        'Sinnvolle Defaults für typische Integration.',
    appModeAdvancedTitle: 'Erweitert (Lab)',
    appModeAdvancedDescription:
        'Alle SDK-Einstellungen, gruppiert nach Echtzeit-Modus. '
        'Genutzt von /observa-noma-Sitzungen.',
    basicOnboardingTitle: 'Basis-Setup',
    basicOnboardingIntro:
        'Echtes CHT-Backend mit minimaler Konfiguration. Für Mock-Daten '
        'ohne Setup wähle Demo aus dem Selector; für alle SDK-'
        'Einstellungen, Erweitert.',
    advSectionGlobal: 'Global',
    advSectionRealtime: 'Echtzeit',
    advSseIdleTimeout: 'SSE Idle-Timeout (s)',
    advSseIdleTimeoutTip:
        'SSE neu verbinden wenn in diesem Fenster keine Chunks '
        'eintreffen. Standard 60 s. 0 deaktiviert den Watchdog.',
    advPollMaxRoomsPerTick: 'Max Räume pro Tick',
    advPollMaxRoomsPerTickTip:
        'Obergrenze für messages.list pro Polling-Tick. Standard 10. '
        'Schützt das Backend bei vielen gleichzeitigen Änderungen.',
    advManualHint:
        'Manueller Modus hat keinen Background-Kanal — Updates kommen '
        'nur bei Refresh / Pull-to-Refresh.',
    advRequestTimeout: 'Request-Timeout (s)',
    advRequestTimeoutTip:
        'REST-Timeout pro Aufruf in Sekunden. Standard 30. Niedriger '
        'setzen für Retry-/Banner-UX; höher bei wackeligen Netzen.',
    advWsReconnectDelay: 'WS-Reconnect-Verzögerung (s)',
    advWsReconnectDelayTip:
        'Basisverzögerung zwischen WebSocket-Reconnect-Versuchen. Das SDK '
        'wendet exponentielles Backoff darüber an. Standard 2 — passt zum '
        'CHT-Keepalive-Fenster, sodass ein vorübergehender Abbruch in ~5s '
        'reconnectet.',
    advMaxReconnect: 'Max. Reconnect-Versuche',
    advMaxReconnectTip:
        'Wie oft das SDK den WebSocket erneut versucht, bevor es aufgibt '
        'und einen dauerhaft getrennten Status anzeigt. Leer (Standard) = '
        'unendlich — versucht es ewig mit Backoff.',
    advEventBuffer: 'Event-Puffergröße',
    advEventBufferTip:
        'Maximale Anzahl Echtzeit-Events, die im Speicher gepuffert werden, '
        'während die App nicht abonniert ist (z. B. im Hintergrund). '
        'Standard 0 — ungepuffert, das SDK verwirft Events älter als der '
        'letzte Sync. Auf 100+ erhöhen für reichhaltigere Wiedergabe beim '
        'Fortsetzen.',
    demoModeTitle: 'Demomodus',
    demoModeBodyTechnical:
        'Produktreife Chat-Infrastruktur für echte Apps. '
        'Echtzeit-Messaging, Offline-Persistenz, Moderationswerkzeuge '
        'und ein ausgereiftes Flutter-SDK — entwickelt, gehostet und '
        'betrieben von Nomasystems im großen Maßstab. Du lieferst das '
        'Produkt; wir betreiben das Messaging.',
    demoModeBodyCommercial:
        'Das vollständige Produkt ist ein schlüsselfertiges Chat-Backend '
        'von Nomasystems mit Admin-Panel, Moderationswerkzeugen, '
        'Broadcast-Räumen, Metrik-Dashboard, Audit-Log, Webhooks und dem '
        'Rest der operativen Oberfläche — nichts davon ist in dieser Demo '
        'enthalten.',
    demoModeRequestPrefix: 'Live-Demo anfragen unter ',
    demoModeFeatureRealtime: 'Echtzeit-Messaging',
    demoModeFeatureOffline: 'Offline-first mit persistentem Cache',
    demoModeFeatureAdmin: 'Admin-Panel, Moderation, Audit-Log',
    demoModeFeatureSdk: 'Flutter-SDK bereit für deine App',
    demoModeCtaLabel: 'Kontakt aufnehmen',
    enterChat: 'Chat betreten',
    openSearch: 'Benutzer suchen',
    closeSearch: 'Suche schließen',
    searchUsersHint: 'Benutzer nach Namen suchen (≥2 Zeichen)',
    suggestionsTitle: 'Vorschläge',
    languageMenu: 'Sprache',
    cancelSelection: 'Auswahl abbrechen',
    selectedCountTemplate: '{count} ausgewählt',
    acceptedInvitationTemplate: 'Einladung zu {name} angenommen',
    acceptedInvitationFallback: 'Raum',
    reportReasonHint: 'Meldegrund',
    globalErrorTemplate: '{kind} fehlgeschlagen: {failure}',
    bannedFromRoom: 'Du wurdest aus diesem Raum gebannt',
    bannedFromRoomWithReasonTemplate:
        'Du wurdest aus diesem Raum gebannt: {reason}',
    leftRoomWithReasonTemplate: 'Du hast diesen Raum verlassen: {reason}',
    leftRoomReasonTemplate: 'Du hast diesen Raum verlassen ({reason})',
    failedToOpenRoomTemplate: 'Raum konnte nicht geöffnet werden: {error}',
  );

  static const ExampleStrings it = ExampleStrings(
    onboardingSubtitle: 'Configura l\'esempio a tuo piacimento',
    modeMock: 'Mock',
    modeReal: 'Reale',
    realIntroBackend: 'Si collega a un backend reale.',
    realIntroMultiInstance: 'Ti servono più istanze su terminali diversi.',
    usernameLabel: 'Il tuo nome',
    usernameHelper: 'Almeno 3 caratteri (es. "alice")',
    backendTitle: 'Backend',
    baseUrlLabel: 'URL base (REST)',
    wsUrlLabel: 'URL WS',
    sseUrlLabel: 'URL SSE',
    advancedTitle: 'Avanzate',
    advRealtimeMode: 'Modalità realtime',
    advRealtimeModeTip:
        'Auto: WS primario con failover SSE (consigliato). '
        'Solo WebSocket: nessun fallback. Solo SSE: salta '
        'l\'handshake WS — utile dietro proxy che bloccano WS. '
        'Polling: tick REST ogni N secondi. Manuale: aggiorna '
        'solo con pull-to-refresh o chat.refresh().',
    advPollingInterval: 'Intervallo polling (s)',
    advPollingIntervalTip:
        'Frequenza dei tick di polling. Default 15 s; l\'SDK rifiuta '
        'valori inferiori a 5 s.',
    advPollUnreadOnly: 'Solo room con non letti',
    advPollUnreadOnlyTip:
        'Quando ON interroga solo le room con messaggi non letti. OFF '
        'consulta tutte le room — più carico sul backend ma cattura '
        'modifiche silenziose.',
    advPollOpenRooms: 'Polling messaggi delle chat aperte',
    advPollOpenRoomsTip:
        'Quando ON ogni tick estrae anche messaggi delle room con un '
        'ChatController attivo. Tradeoff: 1 richiesta extra per tick '
        'per chat aperta.',
    refreshTooltip: 'Aggiorna',
    refreshDone: 'Aggiornato',
    appModeSelectorTitle: 'Scegli come eseguire l\'esempio',
    appModeSelectorIntro:
        'Seleziona un preset. Puoi cambiarlo dopo dal menu dell\'app.',
    appModeDemoTitle: 'Demo',
    appModeDemoDescription:
        'Nessuna configurazione. Dati mock + chat di esempio pronte. '
        'Quello che dimostrano le "5 righe" del README.',
    appModeBasicTitle: 'Base',
    appModeBasicDescription:
        'Onboarding minimo: nome + backend reale opzionale. Defaults '
        'ragionevoli per integrazione tipica.',
    appModeAdvancedTitle: 'Avanzato (Lab)',
    appModeAdvancedDescription:
        'Tutte le opzioni dell\'SDK, raggruppate per modalità realtime. '
        'Usato dalle sessioni /observa-noma.',
    basicOnboardingTitle: 'Setup base',
    basicOnboardingIntro:
        'Backend CHT reale con la configurazione minima. Per dati mock '
        'senza setup scegli Demo dal selettore; per tutte le opzioni '
        'dell\'SDK, Avanzato.',
    advSectionGlobal: 'Globale',
    advSectionRealtime: 'Realtime',
    advSseIdleTimeout: 'Timeout idle SSE (s)',
    advSseIdleTimeoutTip:
        'Riconnette SSE se non arrivano chunk in questo intervallo. '
        'Default 60 s. 0 disabilita il watchdog.',
    advPollMaxRoomsPerTick: 'Max room per tick',
    advPollMaxRoomsPerTickTip:
        'Limite messages.list per tick di polling. Default 10. '
        'Protegge il backend quando molte room cambiano insieme.',
    advManualHint:
        'La modalità manuale non ha canale background — gli '
        'aggiornamenti arrivano solo al refresh / pull-to-refresh.',
    advRequestTimeout: 'Timeout richiesta (s)',
    advRequestTimeoutTip:
        'Timeout REST per chiamata in secondi. Default 30. Abbassalo '
        'per esercitare retry / UX banner; alzalo su reti instabili.',
    advWsReconnectDelay: 'Ritardo riconnessione WS (s)',
    advWsReconnectDelayTip:
        'Ritardo di base tra tentativi di riconnessione WebSocket. L\'SDK '
        'applica backoff esponenziale sopra. Default 2 — combacia con la '
        'finestra keepalive di CHT, quindi un\'interruzione transitoria '
        'riconnette in ~5s.',
    advMaxReconnect: 'Tentativi max di riconnessione',
    advMaxReconnectTip:
        'Quante volte l\'SDK riprova il WebSocket prima di arrendersi ed '
        'esporre uno stato disconnesso persistente. Vuoto (default) = '
        'infinito — riprova per sempre con backoff.',
    advEventBuffer: 'Dimensione buffer eventi',
    advEventBufferTip:
        'Numero massimo di eventi in tempo reale buffer in memoria mentre '
        'l\'app non è sottoscritta (es. in background). Default 0 — senza '
        'buffer, l\'SDK scarta eventi anteriori all\'ultimo sync. Portalo '
        'a 100+ per un replay più ricco alla ripresa.',
    demoModeTitle: 'Modalità demo',
    demoModeBodyTechnical:
        'Infrastruttura chat di produzione per app reali. '
        'Messaggistica in tempo reale, persistenza offline, strumenti '
        'di moderazione e un SDK Flutter curato — progettato, ospitato '
        'e gestito da Nomasystems su larga scala. Tu spedisci il '
        'prodotto; noi facciamo girare la messaggistica.',
    demoModeBodyCommercial:
        'Il prodotto completo è un backend chat chiavi in mano di '
        'Nomasystems con pannello di amministrazione, strumenti di '
        'moderazione, stanze broadcast, dashboard metriche, audit log, '
        'webhook e il resto della superficie operativa — niente di tutto '
        'questo viaggia in questa demo.',
    demoModeRequestPrefix: 'Richiedi una demo dal vivo a ',
    demoModeFeatureRealtime: 'Messaggistica in tempo reale',
    demoModeFeatureOffline: 'Offline-first con cache persistente',
    demoModeFeatureAdmin: 'Pannello admin, moderazione, audit log',
    demoModeFeatureSdk: 'SDK Flutter pronto per la tua app',
    demoModeCtaLabel: 'Contattaci',
    enterChat: 'Entra nella chat',
    openSearch: 'Cerca utenti',
    closeSearch: 'Chiudi ricerca',
    searchUsersHint: 'Cerca utenti per nome (≥2 caratteri)',
    suggestionsTitle: 'Suggerimenti',
    languageMenu: 'Lingua',
    cancelSelection: 'Annulla selezione',
    selectedCountTemplate: '{count} selezionati',
    acceptedInvitationTemplate: 'Invito a {name} accettato',
    acceptedInvitationFallback: 'stanza',
    reportReasonHint: 'Motivo della segnalazione',
    globalErrorTemplate: '{kind} fallito: {failure}',
    bannedFromRoom: 'Sei stato bannato da questa stanza',
    bannedFromRoomWithReasonTemplate:
        'Sei stato bannato da questa stanza: {reason}',
    leftRoomWithReasonTemplate: 'Hai lasciato questa stanza: {reason}',
    leftRoomReasonTemplate: 'Hai lasciato questa stanza ({reason})',
    failedToOpenRoomTemplate: 'Impossibile aprire la stanza: {error}',
  );

  static const ExampleStrings pt = ExampleStrings(
    onboardingSubtitle: 'Configura o exemplo ao teu gosto',
    modeMock: 'Mock',
    modeReal: 'Real',
    realIntroBackend: 'Liga-se a um backend real.',
    realIntroMultiInstance:
        'Precisas de várias instâncias em terminais diferentes.',
    usernameLabel: 'O teu nome',
    usernameHelper: 'Pelo menos 3 caracteres (ex. "alice")',
    backendTitle: 'Backend',
    baseUrlLabel: 'URL base (REST)',
    wsUrlLabel: 'URL WS',
    sseUrlLabel: 'URL SSE',
    advancedTitle: 'Avançado',
    advRealtimeMode: 'Modo de tempo real',
    advRealtimeModeTip:
        'Auto: WS primário com fallback SSE (recomendado). '
        'Só WebSocket: sem fallback. Só SSE: salta o handshake '
        'WS — útil atrás de proxies que bloqueiam WS. Polling: '
        'tick REST cada N segundos. Manual: só refresca com '
        'pull-to-refresh ou chat.refresh().',
    advPollingInterval: 'Intervalo de polling (s)',
    advPollingIntervalTip:
        'Frequência do tick de polling. Padrão 15 s; o SDK rejeita '
        'valores abaixo de 5 s.',
    advPollUnreadOnly: 'Apenas rooms com não lidos',
    advPollUnreadOnlyTip:
        'Quando ON consulta apenas rooms com mensagens não lidas. OFF '
        'consulta todas — mais carga no backend mas apanha edições '
        'silenciosas.',
    advPollOpenRooms: 'Polling mensagens de chats abertos',
    advPollOpenRoomsTip:
        'Quando ON cada tick também busca mensagens de rooms com '
        'ChatController ativo. Tradeoff: 1 request extra por tick por '
        'chat aberto.',
    refreshTooltip: 'Atualizar',
    refreshDone: 'Atualizado',
    appModeSelectorTitle: 'Escolhe como executar o example',
    appModeSelectorIntro:
        'Seleciona um preset. Podes alterar depois no menu da app.',
    appModeDemoTitle: 'Demo',
    appModeDemoDescription:
        'Sem configuração. Dados mock + chats de exemplo prontos a '
        'explorar. O que demonstram as "5 linhas" do README.',
    appModeBasicTitle: 'Básico',
    appModeBasicDescription:
        'Onboarding mínimo: nome + backend real opcional. Defaults '
        'razoáveis para integração típica.',
    appModeAdvancedTitle: 'Avançado (Lab)',
    appModeAdvancedDescription:
        'Todas as opções do SDK, agrupadas por modo realtime. '
        'Usado pelas sessões /observa-noma.',
    basicOnboardingTitle: 'Configuração básica',
    basicOnboardingIntro:
        'Backend CHT real com a configuração mínima. Para dados mock '
        'sem setup escolhe Demo no seletor; para todas as opções do '
        'SDK, Avançado.',
    advSectionGlobal: 'Global',
    advSectionRealtime: 'Tempo real',
    advSseIdleTimeout: 'Timeout idle SSE (s)',
    advSseIdleTimeoutTip:
        'Reconecta SSE se não chegarem chunks neste intervalo. '
        'Padrão 60 s. 0 desativa o watchdog.',
    advPollMaxRoomsPerTick: 'Máx rooms por tick',
    advPollMaxRoomsPerTickTip:
        'Limite de messages.list por tick de polling. Padrão 10. '
        'Protege o backend quando muitos rooms mudam.',
    advManualHint:
        'O modo manual não tem canal em background — atualizações só '
        'chegam ao tocar refresh ou pull-to-refresh.',
    advRequestTimeout: 'Timeout de pedido (s)',
    advRequestTimeoutTip:
        'Timeout REST por chamada em segundos. Por defeito 30. Reduz '
        'para exercitar retry / UX de banner; sobe em redes instáveis.',
    advWsReconnectDelay: 'Atraso de reconexão WS (s)',
    advWsReconnectDelayTip:
        'Atraso base entre tentativas de reconexão WebSocket. O SDK aplica '
        'backoff exponencial por cima. Por defeito 2 — combina com a '
        'janela keepalive de CHT, portanto uma quebra transitória '
        'reconecta em ~5s.',
    advMaxReconnect: 'Tentativas máx. de reconexão',
    advMaxReconnectTip:
        'Quantas vezes o SDK retenta o WebSocket antes de desistir e '
        'expor um estado desligado persistente. Vazio (por defeito) = '
        'infinito — retenta para sempre com backoff.',
    advEventBuffer: 'Tamanho do buffer de eventos',
    advEventBufferTip:
        'Número máximo de eventos em tempo real em buffer em memória '
        'enquanto a app não está subscrita (ex. em background). Por '
        'defeito 0 — sem buffer, o SDK descarta eventos anteriores ao '
        'último sync. Sobe para 100+ para replay mais rico ao retomar.',
    demoModeTitle: 'Modo demo',
    demoModeBodyTechnical:
        'Infraestrutura de chat de produção para apps reais. '
        'Mensagens em tempo real, persistência offline, ferramentas '
        'de moderação e um SDK Flutter polido — concebido, alojado '
        'e operado pela Nomasystems à escala. Tu lanças o produto; '
        'nós operamos a mensageria.',
    demoModeBodyCommercial:
        'O produto completo é um backend de chat chave-na-mão da '
        'Nomasystems com painel de administração, ferramentas de '
        'moderação, salas broadcast, dashboard de métricas, audit log, '
        'webhooks e o resto da superfície operacional — nada disto vai '
        'nesta demo.',
    demoModeRequestPrefix: 'Pede uma demo ao vivo em ',
    demoModeFeatureRealtime: 'Mensagens em tempo real',
    demoModeFeatureOffline: 'Offline-first com cache persistente',
    demoModeFeatureAdmin: 'Painel admin, moderação, audit log',
    demoModeFeatureSdk: 'SDK Flutter pronto para a tua app',
    demoModeCtaLabel: 'Contacta-nos',
    enterChat: 'Entrar no chat',
    openSearch: 'Procurar utilizadores',
    closeSearch: 'Fechar pesquisa',
    searchUsersHint: 'Procurar utilizadores por nome (≥2 caracteres)',
    suggestionsTitle: 'Sugestões',
    languageMenu: 'Idioma',
    cancelSelection: 'Cancelar seleção',
    selectedCountTemplate: '{count} selecionados',
    acceptedInvitationTemplate: 'Convite para {name} aceite',
    acceptedInvitationFallback: 'sala',
    reportReasonHint: 'Motivo da denúncia',
    globalErrorTemplate: '{kind} falhou: {failure}',
    bannedFromRoom: 'Foste banido desta sala',
    bannedFromRoomWithReasonTemplate: 'Foste banido desta sala: {reason}',
    leftRoomWithReasonTemplate: 'Saíste desta sala: {reason}',
    leftRoomReasonTemplate: 'Saíste desta sala ({reason})',
    failedToOpenRoomTemplate: 'Não foi possível abrir a sala: {error}',
  );

  static const ExampleStrings ca = ExampleStrings(
    onboardingSubtitle: 'Configura l\'exemple al teu gust',
    modeMock: 'Mock',
    modeReal: 'Real',
    realIntroBackend: 'Es connecta a un backend real.',
    realIntroMultiInstance:
        'Necessites diverses instàncies en terminals diferents.',
    usernameLabel: 'El teu nom',
    usernameHelper: 'Almenys 3 caràcters (p. ex. "alice")',
    backendTitle: 'Backend',
    baseUrlLabel: 'URL base (REST)',
    wsUrlLabel: 'URL WS',
    sseUrlLabel: 'URL SSE',
    advancedTitle: 'Avançat',
    advRealtimeMode: 'Mode en temps real',
    advRealtimeModeTip:
        'Auto: WS primari amb failover SSE (recomanat). '
        'Només WebSocket: sense fallback. Només SSE: salta '
        'l\'handshake WS — útil darrere de proxys que bloquegen '
        'WS. Polling: tick REST cada N segons. Manual: només '
        'refresca amb pull-to-refresh o chat.refresh().',
    advPollingInterval: 'Interval de polling (s)',
    advPollingIntervalTip:
        'Cada quant fa tick el motor de polling. Per defecte 15 s; '
        'el SDK rebutja valors per sota de 5 s.',
    advPollUnreadOnly: 'Només rooms amb no llegits',
    advPollUnreadOnlyTip:
        'Quan està ON pregunta només per rooms amb missatges no '
        'llegits. OFF consulta tots els rooms — més càrrega al '
        'backend però captura edicions silencioses.',
    advPollOpenRooms: 'Polling missatges dels xats oberts',
    advPollOpenRoomsTip:
        'Quan està ON cada tick també extreu missatges de rooms amb '
        'un ChatController actiu. Compromís: 1 sol·licitud extra per '
        'tick per xat obert.',
    refreshTooltip: 'Actualitza',
    refreshDone: 'Actualitzat',
    appModeSelectorTitle: 'Tria com executar l\'example',
    appModeSelectorIntro:
        'Selecciona un preset. Pots canviar-lo després des del menú.',
    appModeDemoTitle: 'Demo',
    appModeDemoDescription:
        'Sense configuració. Dades mock + xats d\'exemple llestos. '
        'El que demostren les "5 línies" del README.',
    appModeBasicTitle: 'Bàsic',
    appModeBasicDescription:
        'Onboarding mínim: nom + backend real opcional. Defaults '
        'raonables per integració típica.',
    appModeAdvancedTitle: 'Avançat (Lab)',
    appModeAdvancedDescription:
        'Totes les opcions de l\'SDK, agrupades per mode realtime. '
        'Usat per les sessions /observa-noma.',
    basicOnboardingTitle: 'Configuració bàsica',
    basicOnboardingIntro:
        'Backend CHT real amb la configuració mínima. Per a dades mock '
        'sense setup tria Demo des del selector; per a totes les opcions '
        'de l\'SDK, Avançat.',
    advSectionGlobal: 'Global',
    advSectionRealtime: 'Temps real',
    advSseIdleTimeout: 'Timeout idle SSE (s)',
    advSseIdleTimeoutTip:
        'Reconnecta SSE si no arriben chunks en aquest interval. Per '
        'defecte 60 s. 0 desactiva el watchdog.',
    advPollMaxRoomsPerTick: 'Màx rooms per tick',
    advPollMaxRoomsPerTickTip:
        'Límit de messages.list per tick de polling. Per defecte 10. '
        'Protegeix el backend quan molts rooms canvien.',
    advManualHint:
        'El mode manual no té canal en background — les '
        'actualitzacions només arriben en tocar refresh o pull-to-refresh.',
    advRequestTimeout: 'Temps d\'espera de la petició (s)',
    advRequestTimeoutTip:
        'Temps d\'espera REST per crida en segons. Per defecte 30. '
        'Baixa\'l per exercitar reintents / UX de banner; puja\'l en '
        'xarxes inestables.',
    advWsReconnectDelay: 'Retard de reconnexió WS (s)',
    advWsReconnectDelayTip:
        'Retard base entre intents de reconnexió del WebSocket. El SDK '
        'aplica backoff exponencial per sobre. Per defecte 2 — encaixa '
        'amb la finestra keepalive de CHT, així una caiguda transitòria '
        'reconnecta en ~5s.',
    advMaxReconnect: 'Intents màxims de reconnexió',
    advMaxReconnectTip:
        'Quantes vegades el SDK reintenta el WebSocket abans de rendir-se '
        'i exposar un estat desconnectat persistent. Buit (per defecte) = '
        'infinit — reintenta per sempre amb backoff.',
    advEventBuffer: 'Mida del buffer d\'esdeveniments',
    advEventBufferTip:
        'Nombre màxim d\'esdeveniments en temps real en buffer en memòria '
        'mentre l\'app no està subscrita (p. ex. en segon pla). Per '
        'defecte 0 — sense buffer, el SDK descarta esdeveniments '
        'anteriors a l\'últim sync. Puja a 100+ per a un replay més ric '
        'al reprendre.',
    demoModeTitle: 'Mode demo',
    demoModeBodyTechnical:
        'Infraestructura de xat de producció per a apps reals. '
        'Missatgeria en temps real, persistència offline, eines de '
        'moderació i un SDK Flutter polit — dissenyat, allotjat i '
        'operat per Nomasystems a escala. Tu llences el producte; '
        'nosaltres operem la missatgeria.',
    demoModeBodyCommercial:
        'El producte complet és un backend de xat clau en mà de '
        'Nomasystems amb panell d\'administració, eines de moderació, '
        'sales broadcast, tauler de mètriques, audit log, webhooks i la '
        'resta de la superfície operativa — res d\'això viatja en aquesta '
        'demo.',
    demoModeRequestPrefix: 'Demana una demo en directe a ',
    demoModeFeatureRealtime: 'Missatgeria en temps real',
    demoModeFeatureOffline: 'Offline-first amb caché persistent',
    demoModeFeatureAdmin: 'Panel admin, moderació, audit log',
    demoModeFeatureSdk: 'SDK Flutter llest per a la teva app',
    demoModeCtaLabel: 'Contacta\'ns',
    enterChat: 'Entra al xat',
    openSearch: 'Cerca usuaris',
    closeSearch: 'Tanca la cerca',
    searchUsersHint: 'Cerca usuaris per nom (≥2 caràcters)',
    suggestionsTitle: 'Suggeriments',
    languageMenu: 'Idioma',
    cancelSelection: 'Cancel·la la selecció',
    selectedCountTemplate: '{count} seleccionats',
    acceptedInvitationTemplate: 'Invitació a {name} acceptada',
    acceptedInvitationFallback: 'sala',
    reportReasonHint: 'Motiu de la denúncia',
    globalErrorTemplate: '{kind} ha fallat: {failure}',
    bannedFromRoom: 'T\'han expulsat d\'aquesta sala',
    bannedFromRoomWithReasonTemplate:
        'T\'han expulsat d\'aquesta sala: {reason}',
    leftRoomWithReasonTemplate: 'Has sortit d\'aquesta sala: {reason}',
    leftRoomReasonTemplate: 'Has sortit d\'aquesta sala ({reason})',
    failedToOpenRoomTemplate: 'No s\'ha pogut obrir la sala: {error}',
  );
}
