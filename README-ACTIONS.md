# Momentum senza Mac — pipeline GitHub Actions

Build su runner macOS di GitHub → `.ipa` non firmato come artifact → firma e
installazione sul telefono con SideStore o Sideloadly. Nessun Mac in nessun punto.

## Cosa è stato aggiunto al handoff originale

| File | Scopo |
|---|---|
| `project.yml` | Spec XcodeGen: genera `Momentum.xcodeproj` (app + widget extension, target membership condivisa per Models/Theme/Viz, entitlements, Info.plist) direttamente sul runner. Non serve mai creare il progetto a mano in Xcode. |
| `.github/workflows/build.yml` | Workflow: XcodeGen → `xcodebuild` unsigned per device → impacchetta `Momentum-unsigned.ipa` → artifact scaricabile. |
| Patch a `Sources/App/Models.swift` | `AppGroup.id` ora si risolve a runtime leggendo l'`embedded.mobileprovision`: se il re-sign (Sideloadly/SideStore/account gratuito) rinomina l'App Group, app e widget continuano a condividere i dati. |

## Setup (una volta sola)

1. Crea un repo GitHub (privato va bene: ~200 min macOS/mese gratis, questa build ne usa ~5-8).
2. Push di tutto il contenuto di questa cartella (inclusa `.github/`).
3. Tab **Actions** → il workflow parte da solo sul push su `main` (o lancialo con *Run workflow*).
4. A build verde: scarica l'artifact **Momentum-unsigned-ipa**.

## Firma e installazione (senza Mac)

**Opzione A — Sideloadly (qualsiasi PC Windows, quando ne hai uno sottomano):**
1. Collega l'iPhone, trascina l'ipa, login con Apple ID (gratuito).
2. **Advanced options** → abilita la firma delle app extension (i widget sono
   un'extension: se viene rimossa, l'app parte ma i widget non esistono).
3. Se disponibile, abilita anche il supporto App Groups. Se il group viene
   rinominato, la patch a `Models.swift` lo gestisce.
4. Sul telefono: Impostazioni → Generali → VPN e gestione dispositivo → autorizza il profilo.

**Opzione B — SideStore (tutto on-device dopo il primo setup):**
firma e refresh direttamente dall'iPhone; il refresh dei 7 giorni si fa senza PC.
Il primo pairing richiede un computer una volta sola.

**Nota account gratuito:** firma valida 7 giorni (come per NOOP), max 3 app
installate contemporaneamente, e HealthKit + App Groups sono capability ammesse
anche sul personal team gratuito.

## Loop di iterazione

1. Modifichi i file Swift (va bene anche l'editor web di GitHub o l'app mobile).
2. Push su `main` → nuova build → nuovo artifact (~5-8 min).
3. Re-firma e reinstalla.

Se la build fallisce, il log mostra le righe `error:` direttamente nello step
(e l'intero `xcodebuild.log` viene caricato come artifact): incollale a Claude
e ottieni la patch.

## Limiti noti

- **Niente simulatore**: si testa solo su device. Per iterare sui visual senza
  installare ogni volta, apri `design/Widget Concepts.dc.html` nel browser —
  è la source of truth dei renderer.
- **HealthKit su device**: la prima run chiede i permessi; in assenza di dati
  usa `seedSampleData()` dello store (già previsto per dev).
- I bundle id in `project.yml` (`com.alessandro.momentum[.widgets]`) vengono
  comunque riscritti dal tool di firma sul tuo team — non serve toccarli.
