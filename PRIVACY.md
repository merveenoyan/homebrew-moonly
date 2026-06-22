# Privacy Policy

**Moonly — Menstrual Cycle Tracker**
*Last updated: June 22, 2026*

Moonly is a macOS menu-bar menstrual cycle tracker built by Hugging Face. It is designed with privacy as a core principle: your health data never leaves your device.

## Data We Collect

Moonly does **not** collect, transmit, or store any personal data on external servers. All data is entered by you and stays on your Mac.

### Health Data You Enter

- Period and flow tracking (dates, intensity)
- Symptoms (cramps, headache, bloating, and others)
- Mood and energy levels
- Free-text notes (up to 200 characters)

### Data the App Computes Locally

- Cycle length, period length, and phase predictions
- Fertile window and ovulation estimates
- AI-generated phase inference and personalized recommendations (powered by an on-device language model)

## Where Your Data Is Stored

All data is stored **locally on your Mac**, encrypted at rest using AES-256-GCM (via Apple CryptoKit). The encryption key is stored in the macOS Keychain.

| Data | Location |
|------|----------|
| Symptom logs | `~/Library/Application Support/Moonly/data.json` (encrypted) |
| AI recommendations | `~/Library/Application Support/Moonly/recommendations.json` (encrypted) |
| Phase inference | `~/Library/Application Support/Moonly/phase_inference.json` (encrypted) |
| Model weights | `~/Library/Application Support/Moonly/models/` |
| Encryption key | macOS Keychain |

There is no iCloud sync, no cloud backup, and no remote database.

## Network Usage

Moonly makes **one network request**: downloading the AI model (~5 GB) from Hugging Face Hub on first launch. This is the only time the app connects to the internet.

- **No analytics or telemetry** is collected
- **No crash reporting** is sent
- **No usage data** is transmitted
- **No advertising identifiers** are used

## Third-Party Services

Moonly does not integrate any third-party analytics, advertising, or tracking services.

The only third-party interaction is the one-time model download from [Hugging Face Hub](https://huggingface.co), which is subject to [Hugging Face's Privacy Policy](https://huggingface.co/privacy).

## User Accounts

Moonly does not require or support user accounts, login, sign-up, or any form of authentication.

## Permissions

Moonly may request the following macOS permissions:

- **Notifications** — to send optional daily guidance reminders (local notifications only; no push notification server is involved)
- **Network access** (App Store version only) — for the one-time model download

Moonly does not access your camera, microphone, contacts, calendar, location, or HealthKit.

## Data Retention and Deletion

Your data exists only on your device. To delete all data:

1. Remove the app, or
2. Delete the folder `~/Library/Application Support/Moonly/`

If installed via Homebrew, running `brew uninstall --zap moonly` removes all associated data.

## Children's Privacy

Moonly does not knowingly collect data from children under 13. Since all data is stored locally and never transmitted, no personal information of any user reaches our servers.

## Medical Disclaimer

Moonly provides general wellness suggestions and is not a medical device. Predictions and recommendations are heuristic and should not be used as contraceptive guidance or a substitute for professional medical advice.

## Changes to This Policy

If this policy is updated, the revision date at the top will be changed. Since Moonly does not collect contact information, we encourage you to review this page periodically.

## Contact

If you have questions about this privacy policy, you can reach out via:

- GitHub Issues on the [Moonly repository](https://github.com/huggingface/moonly)
- Hugging Face: [https://huggingface.co](https://huggingface.co)
