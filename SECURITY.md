# Security Guidelines

## 🔒 Machine Confidential Information

This repository contains configuration files for development/demo purposes. When deploying to production or contributing, please ensure:

### Backend Configuration
- `backend/.env` - Contains development settings (excluded from git)
- Set your own Google Cloud credentials and bucket names for production

### Android Build Configuration
- `android/key.properties` - Android signing configuration (excluded from git)
- `android/app/*.keystore` - Android signing keystores (excluded from git)

### Production Deployment
- Use environment variables or secure secret management services
- Never commit API keys, passwords, or private keys to the repository
- The demo backend URL in the Flutter app is public and safe for open source

## 🛡️ Security Measures Implemented

✅ All sensitive files are properly excluded via `.gitignore`  
✅ No API keys or secrets are hardcoded in the source code  
✅ Backend uses Google Cloud service authentication  
✅ Demo URLs are safe for public repositories  

## 📞 Security Issues

If you discover a security vulnerability, please report it responsibly by creating a private issue or contacting the maintainers directly.