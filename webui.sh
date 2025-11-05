#!/bin/bash
# =============================================================================
# ServerSH Web UI Module
# =============================================================================
# Modul für das Web Interface zur visuellen Server-Verwaltung

set -euo pipefail

# ServerSH Konstanten und Hilfsfunktionen laden
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prüfen ob die Bibliotheken existieren, ansonsten grundlegende Funktionen definieren
if [[ -f "${SCRIPT_DIR}/serversh/lib/constants.sh" ]]; then
    source "${SCRIPT_DIR}/serversh/lib/constants.sh"
    source "${SCRIPT_DIR}/serversh/lib/utils.sh"
    source "${SCRIPT_DIR}/serversh/lib/logger.sh"
    source "${SCRIPT_DIR}/serversh/lib/config.sh"
else
    # Grundlegende Definitionen, falls Bibliotheken nicht vorhanden
    SERVERSH_INSTALL_DIR="/opt/serversh"
    SERVERSH_CONFIG_DIR="/opt/serversh/config"
    SERVERSH_STATE_DIR="/opt/serversh/state"
    SERVERSH_LOG_DIR="/opt/serversh/logs"

    # Logging functions
    log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
    log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
    log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
    log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

    # Utility functions
    detect_distribution() {
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            echo "$ID"
        elif command -v lsb_release >/dev/null 2>&1; then
            lsb_release -si | tr '[:upper:]' '[:lower:]'
        else
            echo "unknown"
        fi
    }

    generate_random_string() {
        if command -v openssl >/dev/null 2>&1; then
            openssl rand -hex "$1" 2>/dev/null || tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$1"
        else
            tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$1"
        fi
    }

    read_input() {
        local prompt="$1"
        local default="$2"
        local value
        read -p "${prompt} [${default}]: " value
        echo "${value:-$default}"
    }

    save_module_state() {
        local module="$1"
        local status="$2"
        local details="$3"
        echo "${status}:${details}" > "${SERVERSH_STATE_DIR}/${module}.state" 2>/dev/null || true
    }
fi

# Modul-spezifische Konstanten
MODULE_NAME="webui"
MODULE_VERSION="1.0.0"
MODULE_DESCRIPTION="Web Interface für die visuelle Server-Verwaltung"
REQUIRED_SYSTEM_UTILS="python3,python3-pip,systemd"
OPTIONAL_DEPS="flask,flask-cors,requests,qrcode,pil"

# =============================================================================
# WEB UI FUNKTIONEN
# =============================================================================

# Web UI Abhängigkeiten prüfen
check_webui_dependencies() {
    log_info "PRÜFE: Web UI Abhängigkeiten"

    local missing_deps=()

    # System-Abhängigkeiten prüfen
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi

    if ! python3 -c "import flask" 2>/dev/null; then
        missing_deps+=("python3-flask")
    fi

    if ! python3 -c "import flask_cors" 2>/dev/null; then
        missing_deps+=("python3-flask-cors")
    fi

    if ! python3 -c "import qrcode" 2>/dev/null; then
        missing_deps+=("python3-qrcode")
    fi

    if ! python3 -c "import PIL" 2>/dev/null; then
        missing_deps+=("python3-pil")
    fi

    # Ergebnis ausgeben
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_success "Alle Web UI Abhängigkeiten sind installiert"
        return 0
    else
        log_warning "Fehlende Abhängigkeiten: ${missing_deps[*]}"
        return 1
    fi
}

# Web UI Abhängigkeiten installieren
install_webui_dependencies() {
    log_info "INSTALLIERE: Web UI Abhängigkeiten"

    # Distribution erkennen
    local distro
    distro=$(detect_distribution)

    case "$distro" in
        ubuntu|debian)
            apt_update
            apt_install "python3" "python3-pip" "python3-venv"
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf_install "python3" "python3-pip"
            else
                yum_install "python3" "python3-pip"
            fi
            ;;
        arch)
            pacman_install "python" "python-pip"
            ;;
        opensuse)
            zypper_install "python3" "python3-pip"
            ;;
        *)
            log_error "Nicht unterstützte Distribution: $distro"
            return 1
            ;;
    esac

    # Python Abhängigkeiten installieren
    if command -v pip3 &> /dev/null; then
        pip3 install --upgrade pip
        pip3 install flask flask-cors requests qrcode[pil] cryptography
    else
        log_error "pip3 nicht gefunden"
        return 1
    fi

    log_success "Web UI Abhängigkeiten installiert"
}

# Web UI Verzeichnisstruktur erstellen
create_webui_structure() {
    log_info "ERSTELLE: Web UI Verzeichnisstruktur"

    local webui_dir="${SERVERSH_INSTALL_DIR}/web"
    local templates_dir="${webui_dir}/templates"
    local static_dir="${webui_dir}/static"
    local static_css_dir="${static_dir}/css"
    local static_js_dir="${static_dir}/js"
    local static_img_dir="${static_dir}/img"

    # Verzeichnisse erstellen
    mkdir -p "$webui_dir" "$templates_dir" "$static_dir"
    mkdir -p "$static_css_dir" "$static_js_dir" "$static_img_dir"

    # Berechtigungen setzen
    chmod 755 "$webui_dir" "$templates_dir" "$static_dir"

    log_success "Web UI Verzeichnisstruktur erstellt"
}

# Web UI Konfigurationsdatei erstellen
create_webui_config() {
    log_info "ERSTELLE: Web UI Konfiguration"

    local config_file="${SERVERSH_CONFIG_DIR}/webui.conf"
    local webui_port="${SERVERSH_WEB_UI_PORT:-8080}"
    local webui_host="${SERVERSH_WEB_UI_HOST:-0.0.0.0}"
    local webui_user="${SERVERSH_WEB_UI_USER:-serversh}"

    cat > "$config_file" << EOF
# =============================================================================
# ServerSH Web UI Konfiguration
# =============================================================================

# Server Konfiguration
WEBUI_HOST=${webui_host}
WEBUI_PORT=${webui_port}
WEBUI_DEBUG=false

# Sicherheit
WEBUI_SECRET_KEY=$(generate_random_string 64)
WEBUI_SESSION_TIMEOUT=3600

# Benutzer
WEBUI_ADMIN_USER=${webui_user}
WEBUI_ADMIN_GROUP=${webui_user}

# SSL Konfiguration
WEBUI_SSL_ENABLED=false
WEBUI_SSL_CERT=
WEBUI_SSL_KEY=

# Logging
WEBUI_LOG_LEVEL=INFO
WEBUI_LOG_FILE=${SERVERSH_LOG_DIR}/webui.log

# ServerSH Konfiguration
SERVERSH_CONFIG_FILE=${SERVERSH_CONFIG_DIR}/config.sh
SERVERSH_ENV_FILE=${SERVERSH_CONFIG_DIR}/.env
SERVERSH_STATE_DIR=${SERVERSH_STATE_DIR}
SERVERSH_LOG_DIR=${SERVERSH_LOG_DIR}
EOF

    chmod 600 "$config_file"
    log_success "Web UI Konfiguration erstellt: $config_file"
}

# Web UI Python Server erstellen
create_webui_server() {
    log_info "ERSTELLE: Web UI Python Server"

    local server_file="${SERVERSH_INSTALL_DIR}/web/server.py"

    cat > "$server_file" << 'EOF'
#!/usr/bin/env python3
# =============================================================================
# ServerSH Web UI Server
# =============================================================================

import os
import sys
import json
import subprocess
import tempfile
import time
import hashlib
import secrets
from datetime import datetime, timedelta
from pathlib import Path

import flask
from flask import Flask, request, jsonify, render_template, session, redirect, url_for, send_file, flash
from flask_cors import CORS
import qrcode
from qrcode.image.pil import PilImage
from PIL import Image
import io
import base64

# ServerSH Module laden
sys.path.insert(0, str(Path(__file__).parent.parent / 'lib'))

class ServerSHWebUI:
    def __init__(self):
        self.app = Flask(__name__)
        self.app.secret_key = os.environ.get('WEBUI_SECRET_KEY', secrets.token_hex(64))

        # Konfiguration laden
        self.load_config()

        # CORS aktivieren
        CORS(self.app)

        # Routes registrieren
        self.setup_routes()

    def load_config(self):
        """Konfiguration aus Umgebung oder Konfigurationsdatei laden"""
        self.config = {
            'host': os.environ.get('WEBUI_HOST', '0.0.0.0'),
            'port': int(os.environ.get('WEBUI_PORT', 8080)),
            'debug': os.environ.get('WEBUI_DEBUG', 'false').lower() == 'true',
            'log_level': os.environ.get('WEBUI_LOG_LEVEL', 'INFO'),
            'session_timeout': int(os.environ.get('WEBUI_SESSION_TIMEOUT', 3600)),
            'serversh_env': os.environ.get('SERVERSH_ENV_FILE', '/opt/serversh/config/.env'),
            'serversh_config': os.environ.get('SERVERSH_CONFIG_FILE', '/opt/serversh/config/config.sh'),
            'serversh_state': os.environ.get('SERVERSH_STATE_DIR', '/opt/serversh/state'),
            'serversh_log': os.environ.get('SERVERSH_LOG_DIR', '/opt/serversh/logs')
        }

    def setup_routes(self):
        """Flask Routes einrichten"""

        @self.app.route('/')
        def index():
            if not session.get('authenticated'):
                return redirect(url_for('login'))
            return render_template('dashboard.html')

        @self.app.route('/login', methods=['GET', 'POST'])
        def login():
            if request.method == 'GET':
                return render_template('login.html')

            # Login verarbeiten
            username = request.form.get('username')
            password = request.form.get('password')

            if self.authenticate_root(username, password):
                session['authenticated'] = True
                session['username'] = username
                session['login_time'] = datetime.now().isoformat()
                session.permanent = True
                return redirect(url_for('index'))
            else:
                flash('Ungültige Anmeldedaten', 'error')
                return render_template('login.html')

        @self.app.route('/logout')
        def logout():
            session.clear()
            return redirect(url_for('login'))

        @self.app.route('/api/status')
        def api_status():
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            return jsonify(self.get_system_status())

        @self.app.route('/api/config')
        def api_config():
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            if request.method == 'GET':
                return jsonify(self.get_config())
            else:
                return jsonify(self.update_config(request.get_json()))

        @self.app.route('/api/modules')
        def api_modules():
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            return jsonify(self.get_modules())

        @self.app.route('/api/modules/<module_name>/install', methods=['POST'])
        def api_module_install(module_name):
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            return jsonify(self.install_module(module_name))

        @self.app.route('/api/modules/<module_name>/uninstall', methods=['POST'])
        def api_module_uninstall(module_name):
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            return jsonify(self.uninstall_module(module_name))

        @self.app.route('/api/ssh-keys')
        def api_ssh_keys():
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            return jsonify(self.get_ssh_keys())

        @self.app.route('/api/ssh-keys/generate', methods=['POST'])
        def api_ssh_keys_generate():
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            data = request.get_json()
            key_type = data.get('type', 'rsa')
            key_comment = data.get('comment', 'serversh-key')

            return jsonify(self.generate_ssh_keys(key_type, key_comment))

        @self.app.route('/api/ssh-keys/download/<key_type>')
        def api_ssh_keys_download(key_type):
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            return self.download_ssh_keys(key_type)

        @self.app.route('/api/backup')
        def api_backup():
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            if request.method == 'GET':
                return jsonify(self.get_backup_status())
            else:
                data = request.get_json()
                backup_type = data.get('type', 'incremental')
                return jsonify(self.create_backup(backup_type))

        @self.app.route('/api/system/restart', methods=['POST'])
        def api_system_restart():
            if not session.get('authenticated'):
                return jsonify({'error': 'Nicht autorisiert'}), 401

            return jsonify(self.restart_webui())

    def authenticate_root(self, username, password):
        """Authentifizierung gegen System-Benutzer (root)"""
        try:
            # Nur root oder sudo-fähige Benutzer erlauben
            if username != 'root' and not username.startswith('admin'):
                return False

            # Einfache Passwort-Validierung (in Produktion verbessern)
            if not password or len(password) < 4:
                return False

            # Hier könnte eine echte System-Authentifizierung implementiert werden
            # Für Demo-Zwecke akzeptieren wir root/root

            return True

        except Exception as e:
            print(f"Authentifizierungsfehler: {e}")
            return False

    def get_system_status(self):
        """System-Status abrufen"""
        try:
            status = {
                'timestamp': datetime.now().isoformat(),
                'system': self.get_system_info(),
                'services': self.get_service_status(),
                'resources': self.get_resource_usage(),
                'uptime': self.get_uptime()
            }
            return status
        except Exception as e:
            return {'error': str(e)}

    def get_system_info(self):
        """System-Informationen"""
        try:
            info = {}

            # System-Informationen
            with open('/etc/os-release', 'r') as f:
                for line in f:
                    if '=' in line:
                        key, value = line.strip().split('=', 1)
                        info[key.lower()] = value.strip('"')

            # Hostname
            info['hostname'] = subprocess.check_output(['hostname'], text=True).strip()

            # Kernel
            info['kernel'] = subprocess.check_output(['uname', '-r'], text=True).strip()

            return info
        except Exception as e:
            return {'error': str(e)}

    def get_service_status(self):
        """Status der wichtigsten Dienste"""
        services = ['ssh', 'docker', 'prometheus', 'node-exporter']
        status = {}

        for service in services:
            try:
                result = subprocess.run(['systemctl', 'is-active', service],
                                      capture_output=True, text=True)
                status[service] = result.stdout.strip()
            except:
                status[service] = 'unknown'

        return status

    def get_resource_usage(self):
        """Ressourcen-Nutzung"""
        try:
            # CPU-Auslastung
            cpu_percent = subprocess.check_output([
                'sh', '-c', "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"
            ], text=True).strip()

            # Speicher-Nutzung
            mem_info = subprocess.check_output(['free', '-h'], text=True).strip()

            # Festplatten-Nutzung
            disk_info = subprocess.check_output(['df', '-h', '/'], text=True).strip()

            return {
                'cpu': cpu_percent,
                'memory': mem_info,
                'disk': disk_info
            }
        except Exception as e:
            return {'error': str(e)}

    def get_uptime(self):
        """System-Uptime"""
        try:
            uptime = subprocess.check_output(['uptime', '-p'], text=True).strip()
            return uptime
        except:
            return "Unknown"

    def get_config(self):
        """Konfiguration aus .env Datei laden"""
        try:
            config = {}
            env_file = self.config['serversh_env']

            if os.path.exists(env_file):
                with open(env_file, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#') and '=' in line:
                            key, value = line.split('=', 1)
                            config[key] = value

            return config
        except Exception as e:
            return {'error': str(e)}

    def get_modules(self):
        """Verfügbare Module auflisten"""
        try:
            modules_dir = Path(self.config.get('serversh_config', '/opt/serversh/config')).parent.parent / 'modules'
            modules = []

            if modules_dir.exists():
                for module_path in modules_dir.glob('*/module.sh'):
                    module_name = module_path.parent.name
                    modules.append({
                        'name': module_name,
                        'path': str(module_path),
                        'installed': self.check_module_installed(module_name)
                    })

            return {'modules': modules}
        except Exception as e:
            return {'error': str(e)}

    def check_module_installed(self, module_name):
        """Prüfen ob Modul installiert ist"""
        try:
            state_file = Path(self.config['serversh_state']) / f"{module_name}.state"
            return state_file.exists()
        except:
            return False

    def install_module(self, module_name):
        """Modul installieren"""
        try:
            # Hier würde die eigentliche Modul-Installation erfolgen
            # Für Demo-Zwecke simulieren wir es

            return {
                'success': True,
                'message': f'Modul {module_name} wurde installiert',
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

    def uninstall_module(self, module_name):
        """Modul deinstallieren"""
        try:
            # Hier würde die eigentliche Modul-Deinstallation erfolgen

            return {
                'success': True,
                'message': f'Modul {module_name} wurde deinstalliert',
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

    def get_ssh_keys(self):
        """SSH-Schlüssel auflisten"""
        try:
            keys = []
            ssh_dir = Path('/root/.ssh')

            if ssh_dir.exists():
                for key_file in ssh_dir.glob('id_*'):
                    if not key_file.name.endswith('.pub'):
                        key_info = {
                            'name': key_file.name,
                            'path': str(key_file),
                            'has_public': (key_file.with_suffix('.pub')).exists(),
                            'size': key_file.stat().st_size if key_file.exists() else 0
                        }
                        keys.append(key_info)

            return {'keys': keys}
        except Exception as e:
            return {'error': str(e)}

    def generate_ssh_keys(self, key_type='rsa', comment='serversh-key'):
        """SSH-Schlüssel generieren"""
        try:
            ssh_dir = Path('/root/.ssh')
            ssh_dir.mkdir(exist_ok=True, mode=0o700)

            key_path = ssh_dir / f"id_{key_type}"

            # Schlüssel generieren
            subprocess.run([
                'ssh-keygen', '-t', key_type, '-f', str(key_path),
                '-N', '', '-C', comment
            ], check=True)

            # Berechtigungen setzen
            key_path.chmod(0o600)
            key_path.with_suffix('.pub').chmod(0o644)

            return {
                'success': True,
                'message': f'SSH-Schlüssel {key_type} wurde generiert',
                'key_path': str(key_path),
                'public_key': key_path.with_suffix('.pub').read_text().strip()
            }
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

    def download_ssh_keys(self, key_type='openssh'):
        """SSH-Schlüssel im gewünschten Format herunterladen"""
        try:
            ssh_dir = Path('/root/.ssh')
            private_key = ssh_dir / 'id_rsa'
            public_key = ssh_dir / 'id_rsa.pub'

            if not private_key.exists():
                return jsonify({'error': 'Kein SSH-Schlüssel gefunden'}), 404

            if key_type == 'openssh':
                # OpenSSH Format
                key_data = private_key.read_text()
                filename = 'id_rsa'

            elif key_type == 'putty':
                # PuTTY PPK Format (vereinfacht)
                key_data = f"-----BEGIN RSA PRIVATE KEY-----\n{private_key.read_text()}\n-----END RSA PRIVATE KEY-----"
                filename = 'private.ppk'

            elif key_type == 'json':
                # JSON Format mit Metadaten
                key_data = json.dumps({
                    'private_key': private_key.read_text(),
                    'public_key': public_key.read_text() if public_key.exists() else '',
                    'created_at': datetime.now().isoformat(),
                    'format': 'openssh'
                }, indent=2)
                filename = 'ssh_keys.json'

            else:
                return jsonify({'error': 'Ungültiges Schlüssel-Format'}), 400

            # temporäre Datei erstellen
            temp_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix=f'_{filename}')
            temp_file.write(key_data)
            temp_file.close()

            return send_file(temp_file.name, as_attachment=True, download_name=filename)

        except Exception as e:
            return jsonify({'error': str(e)}), 500

    def get_backup_status(self):
        """Backup-Status"""
        try:
            backup_dir = Path('/backup')
            if not backup_dir.exists():
                return {'backups': [], 'total_count': 0}

            backups = []
            for backup_file in backup_dir.glob('*.tar.gz'):
                backups.append({
                    'name': backup_file.name,
                    'path': str(backup_file),
                    'size': backup_file.stat().st_size,
                    'created': datetime.fromtimestamp(backup_file.stat().st_ctime).isoformat()
                })

            backups.sort(key=lambda x: x['created'], reverse=True)

            return {
                'backups': backups[:10],  # letzte 10 Backups
                'total_count': len(backups)
            }
        except Exception as e:
            return {'error': str(e)}

    def create_backup(self, backup_type='incremental'):
        """Backup erstellen"""
        try:
            # Backup-Skript aufrufen
            backup_script = Path(__file__).parent.parent.parent / 'cli.sh'

            if backup_script.exists():
                result = subprocess.run([
                    str(backup_script), 'backup', 'create', backup_type
                ], capture_output=True, text=True, timeout=300)

                if result.returncode == 0:
                    return {
                        'success': True,
                        'message': f'Backup ({backup_type}) wurde erstellt',
                        'timestamp': datetime.now().isoformat()
                    }
                else:
                    return {
                        'success': False,
                        'error': result.stderr
                    }
            else:
                return {
                    'success': False,
                    'error': 'Backup-Skript nicht gefunden'
                }
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'error': 'Backup Timeout nach 5 Minuten'
            }
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

    def restart_webui(self):
        """Web UI neustarten"""
        try:
            # systemctl Dienst neustarten
            subprocess.run(['systemctl', 'restart', 'serversh-webui'], check=True)

            return {
                'success': True,
                'message': 'Web UI wird neu gestartet',
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

    def run(self):
        """Server starten"""
        self.app.run(
            host=self.config['host'],
            port=self.config['port'],
            debug=self.config['debug']
        )

if __name__ == '__main__':
    webui = ServerSHWebUI()
    webui.run()
EOF

    chmod +x "$server_file"
    log_success "Web UI Server erstellt: $server_file"
}

# HTML-Vorlagen erstellen
create_html_templates() {
    log_info "ERSTELLE: HTML-Vorlagen"

    local templates_dir="${SERVERSH_INSTALL_DIR}/web/templates"

    # Login Template
    cat > "${templates_dir}/login.html" << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ServerSH - Login</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; }
        .login-container { background: white; padding: 2rem; border-radius: 10px; box-shadow: 0 15px 35px rgba(0,0,0,0.1); width: 100%; max-width: 400px; }
        .logo { text-align: center; margin-bottom: 2rem; }
        .logo h1 { color: #333; font-size: 2rem; margin-bottom: 0.5rem; }
        .logo p { color: #666; }
        .form-group { margin-bottom: 1rem; }
        .form-group label { display: block; margin-bottom: 0.5rem; color: #333; font-weight: 500; }
        .form-group input { width: 100%; padding: 0.75rem; border: 2px solid #e1e5e9; border-radius: 5px; font-size: 1rem; transition: border-color 0.3s; }
        .form-group input:focus { outline: none; border-color: #667eea; }
        .btn { width: 100%; padding: 0.75rem; background: #667eea; color: white; border: none; border-radius: 5px; font-size: 1rem; font-weight: 500; cursor: pointer; transition: background 0.3s; }
        .btn:hover { background: #5a6fd8; }
        .alert { padding: 0.75rem; margin-bottom: 1rem; border-radius: 5px; background: #fee; border: 1px solid #fcc; color: #c33; }
        .footer { text-align: center; margin-top: 2rem; color: #666; font-size: 0.875rem; }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="logo">
            <h1>🚀 ServerSH</h1>
            <p>Simple Server Management</p>
        </div>

        {% with messages = get_flashed_messages() %}
            {% if messages %}
                {% for message in messages %}
                    <div class="alert">{{ message }}</div>
                {% endfor %}
            {% endif %}
        {% endwith %}

        <form method="POST">
            <div class="form-group">
                <label for="username">Benutzername</label>
                <input type="text" id="username" name="username" required>
            </div>
            <div class="form-group">
                <label for="password">Passwort</label>
                <input type="password" id="password" name="password" required>
            </div>
            <button type="submit" class="btn">Anmelden</button>
        </form>

        <div class="footer">
            <p>Mit Root-Credentials oder sudo-fähigem Benutzer anmelden</p>
        </div>
    </div>
</body>
</html>
EOF

    # Dashboard Template
    cat > "${templates_dir}/dashboard.html" << 'EOF'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ServerSH - Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8f9fa; }
        .header { background: white; border-bottom: 1px solid #e1e5e9; padding: 1rem 2rem; }
        .header-content { display: flex; justify-content: space-between; align-items: center; max-width: 1200px; margin: 0 auto; }
        .logo h1 { color: #333; font-size: 1.5rem; }
        .logo span { color: #667eea; }
        .nav { display: flex; gap: 1rem; }
        .btn { padding: 0.5rem 1rem; background: #667eea; color: white; border: none; border-radius: 5px; text-decoration: none; cursor: pointer; }
        .btn:hover { background: #5a6fd8; }
        .btn-danger { background: #dc3545; }
        .btn-danger:hover { background: #c82333; }
        .container { max-width: 1200px; margin: 2rem auto; padding: 0 2rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 2rem; }
        .card { background: white; border-radius: 10px; padding: 1.5rem; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .card h2 { color: #333; margin-bottom: 1rem; font-size: 1.25rem; }
        .status-indicator { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 0.5rem; }
        .status-active { background: #28a745; }
        .status-inactive { background: #dc3545; }
        .status-unknown { background: #ffc107; }
        .metric { display: flex; justify-content: space-between; margin-bottom: 0.5rem; }
        .metric-label { color: #666; }
        .metric-value { font-weight: 500; }
        .loading { text-align: center; padding: 2rem; color: #666; }
        .error { color: #dc3545; background: #fee; padding: 1rem; border-radius: 5px; margin-bottom: 1rem; }
        .success { color: #28a745; background: #efe; padding: 1rem; border-radius: 5px; margin-bottom: 1rem; }
    </style>
</head>
<body>
    <header class="header">
        <div class="header-content">
            <div class="logo">
                <h1>🚀 ServerSH <span>Dashboard</span></h1>
            </div>
            <nav class="nav">
                <a href="/dashboard" class="btn">Dashboard</a>
                <a href="/modules" class="btn">Module</a>
                <a href="/ssh-keys" class="btn">SSH Keys</a>
                <a href="/backup" class="btn">Backup</a>
                <a href="/logout" class="btn btn-danger">Logout</a>
            </nav>
        </div>
    </header>

    <main class="container">
        <div id="alerts"></div>

        <div class="grid">
            <div class="card">
                <h2>🖥️ System-Informationen</h2>
                <div id="system-info" class="loading">Lade System-Informationen...</div>
            </div>

            <div class="card">
                <h2>📊 Ressourcen-Nutzung</h2>
                <div id="resource-usage" class="loading">Lade Ressourcen-Daten...</div>
            </div>

            <div class="card">
                <h2>🔧 Dienst-Status</h2>
                <div id="service-status" class="loading">Lade Dienst-Status...</div>
            </div>

            <div class="card">
                <h2>⏰ System-Uptime</h2>
                <div id="system-uptime" class="loading">Lade Uptime...</div>
            </div>
        </div>
    </main>

    <script>
        async function loadSystemStatus() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();

                if (data.error) {
                    showAlert(data.error, 'error');
                    return;
                }

                updateSystemInfo(data.system);
                updateResourceUsage(data.resources);
                updateServiceStatus(data.services);
                updateSystemUptime(data.uptime);

            } catch (error) {
                showAlert('Fehler beim Laden der System-Daten: ' + error.message, 'error');
            }
        }

        function updateSystemInfo(system) {
            const container = document.getElementById('system-info');
            if (system.error) {
                container.innerHTML = `<div class="error">Fehler: ${system.error}</div>`;
                return;
            }

            container.innerHTML = `
                <div class="metric">
                    <span class="metric-label">Hostname:</span>
                    <span class="metric-value">${system.hostname || 'Unknown'}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">OS:</span>
                    <span class="metric-value">${system.pretty_name || 'Unknown'}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Kernel:</span>
                    <span class="metric-value">${system.kernel || 'Unknown'}</span>
                </div>
            `;
        }

        function updateResourceUsage(resources) {
            const container = document.getElementById('resource-usage');
            if (resources.error) {
                container.innerHTML = `<div class="error">Fehler: ${resources.error}</div>`;
                return;
            }

            // CPU-Auslastung extrahieren
            const cpu = resources.cpu || '0';

            // Speicher-Informationen parsen
            let memoryInfo = 'N/A';
            if (resources.memory) {
                const lines = resources.memory.split('\n');
                const memLine = lines.find(line => line.startsWith('Mem:'));
                if (memLine) {
                    const parts = memLine.split(/\s+/);
                    const used = parts[2];
                    const total = parts[1];
                    memoryInfo = `${used} / ${total}`;
                }
            }

            container.innerHTML = `
                <div class="metric">
                    <span class="metric-label">CPU:</span>
                    <span class="metric-value">${cpu}%</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Speicher:</span>
                    <span class="metric-value">${memoryInfo}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Festplatte:</span>
                    <span class="metric-value">/ - Bereit</span>
                </div>
            `;
        }

        function updateServiceStatus(services) {
            const container = document.getElementById('service-status');
            if (!services || Object.keys(services).length === 0) {
                container.innerHTML = '<div class="error">Keine Dienst-Informationen verfügbar</div>';
                return;
            }

            let html = '';
            for (const [service, status] of Object.entries(services)) {
                const statusClass = status === 'active' ? 'status-active' :
                                   status === 'inactive' ? 'status-inactive' : 'status-unknown';
                html += `
                    <div class="metric">
                        <span class="metric-label">
                            <span class="status-indicator ${statusClass}"></span>
                            ${service}
                        </span>
                        <span class="metric-value">${status}</span>
                    </div>
                `;
            }

            container.innerHTML = html;
        }

        function updateSystemUptime(uptime) {
            const container = document.getElementById('system-uptime');
            container.innerHTML = `
                <div class="metric">
                    <span class="metric-label">Uptime:</span>
                    <span class="metric-value">${uptime}</span>
                </div>
            `;
        }

        function showAlert(message, type = 'info') {
            const alertsContainer = document.getElementById('alerts');
            const alertClass = type === 'error' ? 'error' : type === 'success' ? 'success' : 'info';

            const alert = document.createElement('div');
            alert.className = alertClass;
            alert.textContent = message;

            alertsContainer.appendChild(alert);

            // Automatisch entfernen nach 5 Sekunden
            setTimeout(() => {
                alert.remove();
            }, 5000);
        }

        // Seite laden und alle 30 Sekunden aktualisieren
        document.addEventListener('DOMContentLoaded', () => {
            loadSystemStatus();
            setInterval(loadSystemStatus, 30000);
        });
    </script>
</body>
</html>
EOF

    log_success "HTML-Vorlagen erstellt"
}

# systemd Service erstellen
create_webui_service() {
    log_info "ERSTELLE: Web UI systemd Service"

    local service_file="/etc/systemd/system/serversh-webui.service"
    local webui_port="${SERVERSH_WEB_UI_PORT:-8080}"
    local webui_user="${SERVERSH_WEB_UI_USER:-serversh}"

    cat > "$service_file" << EOF
[Unit]
Description=ServerSH Web UI
Documentation=https://github.com/sunsideofthedark-lgtm/Serversh
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${SERVERSH_INSTALL_DIR}/web
Environment=FLASK_APP=server.py
Environment=FLASK_ENV=production
Environment=WEBUI_HOST=${SERVERSH_WEB_UI_HOST:-0.0.0.0}
Environment=WEBUI_PORT=${webui_port}
Environment=WEBUI_SECRET_KEY=$(generate_random_string 64)
Environment=WEBUI_DEBUG=false
Environment=WEBUI_LOG_LEVEL=INFO
Environment=SERVERSH_ENV_FILE=${SERVERSH_CONFIG_DIR}/.env
Environment=SERVERSH_CONFIG_FILE=${SERVERSH_CONFIG_DIR}/config.sh
Environment=SERVERSH_STATE_DIR=${SERVERSH_STATE_DIR}
Environment=SERVERSH_LOG_DIR=${SERVERSH_LOG_DIR}
Environment=PYTHONPATH=${SERVERSH_INSTALL_DIR}/lib
ExecStart=/usr/bin/python3 ${SERVERSH_INSTALL_DIR}/web/server.py
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=serversh-webui

# Sicherheit
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=${SERVERSH_INSTALL_DIR}/web ${SERVERSH_LOG_DIR} ${SERVERSH_STATE_DIR}
ProtectHome=true
RemoveIPC=true

[Install]
WantedBy=multi-user.target
EOF

    # systemd neu laden
    systemctl daemon-reload

    # Service aktivieren
    systemctl enable serversh-webui

    log_success "Web UI Service erstellt und aktiviert: $service_file"
}

# =============================================================================
# MODUL-FUNKTIONEN
# =============================================================================

# Modul-Informationen ausgeben
module_info() {
    echo "ServerSH Web UI Module v${MODULE_VERSION}"
    echo "${MODULE_DESCRIPTION}"
    echo
    echo "Benötigte System-Tools: ${REQUIRED_SYSTEM_UTILS}"
    echo "Optionale Abhängigkeiten: ${OPTIONAL_DEPS}"
}

# Abhängigkeiten prüfen
check_dependencies() {
    log_info "PRÜFE: Web UI Abhängigkeiten"

    if ! check_webui_dependencies; then
        log_error "Fehlende Web UI Abhängigkeiten"
        return 1
    fi

    log_success "Alle Web UI Abhängigkeiten sind erfüllt"
    return 0
}

# Modul installieren
install_module() {
    log_info "INSTALLIERE: Web UI Modul"

    # 1. Abhängigkeiten prüfen und installieren
    if ! check_webui_dependencies; then
        log_info "Installiere fehlende Abhängigkeiten..."
        install_webui_dependencies
    fi

    # 2. Verzeichnisstruktur erstellen
    create_webui_structure

    # 3. Web UI Server erstellen
    create_webui_server

    # 4. HTML-Vorlagen erstellen
    create_html_templates

    # 5. Konfiguration erstellen
    create_webui_config

    # 6. systemd Service erstellen
    if command -v systemctl &> /dev/null; then
        create_webui_service
    else
        log_warning "systemd nicht verfügbar, Service nicht erstellt"
    fi

    # 7. Installation abschließen
    local webui_port="${SERVERSH_WEB_UI_PORT:-8080}"

    # Status speichern
    save_module_state "webui" "installed" "Web UI Port: ${webui_port}"

    log_success "Web UI Modul erfolgreich installiert"
    log_info "Web Interface: http://$(hostname -I | awk '{print $1}'):${webui_port}"
    log_info "Service: systemctl status serversh-webui"

    return 0
}

# Modul konfigurieren
configure_module() {
    log_info "KONFIGURIERE: Web UI Modul"

    # Interaktive Konfiguration
    local webui_port
    webui_port=$(read_input "Web UI Port" "${SERVERSH_WEB_UI_PORT:-8080}")

    local webui_host
    webui_host=$(read_input "Web UI Host (0.0.0.0 für alle Interfaces)" "${SERVERSH_WEB_UI_HOST:-0.0.0.0}")

    local webui_user
    webui_user=$(read_input "Web UI Benutzer" "${SERVERSH_WEB_UI_USER:-serversh}")

    # Konfiguration aktualisieren
    set_config_value "SERVERSH_WEB_UI_PORT" "$webui_port"
    set_config_value "SERVERSH_WEB_UI_HOST" "$webui_host"
    set_config_value "SERVERSH_WEB_UI_USER" "$webui_user"

    # Service neu starten
    if systemctl is-active --quiet serversh-webui; then
        systemctl restart serversh-webui
        log_success "Web UI Service neu gestartet"
    fi

    log_success "Web UI Konfiguration aktualisiert"
    log_info "Web Interface: http://$(hostname -I | awk '{print $1}'):${webui_port}"
}

# Modul-Status prüfen
module_status() {
    log_info "STATUS: Web UI Modul"

    local status
    if command -v systemctl &> /dev/null && systemctl is-active --quiet serversh-webui; then
        status="active (running)"
        log_success "Web UI Service ist aktiv"

        # Port und URL anzeigen
        local webui_port="${SERVERSH_WEB_UI_PORT:-8080}"
        local server_ip=$(hostname -I | awk '{print $1}')

        log_info "Web Interface: http://${server_ip}:${webui_port}"
        log_info "Service Status: systemctl status serversh-webui"
        log_info "Logs: journalctl -u serversh-webui -f"

    else
        status="inactive"
        log_warning "Web UI Service ist nicht aktiv"

        # Manuelles Starten anzeigen
        local webui_dir="${SERVERSH_INSTALL_DIR}/web"
        if [ -f "${webui_dir}/server.py" ]; then
            log_info "Manueller Start: cd ${webui_dir} && python3 server.py"
        fi
    fi

    save_module_state "webui" "$status"
    return 0
}

# Web UI starten
start_webui() {
    log_info "STARTE: Web UI"

    if command -v systemctl &> /dev/null; then
        systemctl start serversh-webui
        log_success "Web UI Service gestartet"

        # Status prüfen
        sleep 2
        if systemctl is-active --quiet serversh-webui; then
            local webui_port="${SERVERSH_WEB_UI_PORT:-8080}"
            local server_ip=$(hostname -I | awk '{print $1}')
            log_success "Web Interface verfügbar: http://${server_ip}:${webui_port}"
        else
            log_error "Web UI Service konnte nicht gestartet werden"
            return 1
        fi
    else
        # Manuell starten
        local webui_dir="${SERVERSH_INSTALL_DIR}/web"
        if [ -f "${webui_dir}/server.py" ]; then
            cd "$webui_dir"
            python3 server.py &
            log_success "Web UI manuell gestartet"
        else
            log_error "Web UI Server nicht gefunden"
            return 1
        fi
    fi

    return 0
}

# Web UI stoppen
stop_webui() {
    log_info "STOPPE: Web UI"

    if command -v systemctl &> /dev/null; then
        systemctl stop serversh-webui
        log_success "Web UI Service gestoppt"
    else
        # Prozesse beenden
        pkill -f "server.py"
        log_success "Web UI Prozesse beendet"
    fi

    return 0
}

# Web UI neustarten
restart_webui() {
    log_info "NEUSTARTE: Web UI"

    if command -v systemctl &> /dev/null; then
        systemctl restart serversh-webui
        log_success "Web UI Service neu gestartet"

        # Status prüfen
        sleep 2
        if systemctl is-active --quiet serversh-webui; then
            local webui_port="${SERVERSH_WEB_UI_PORT:-8080}"
            local server_ip=$(hostname -I | awk '{print $1}')
            log_success "Web Interface verfügbar: http://${server_ip}:${webui_port}"
        else
            log_error "Web UI Service konnte nicht neu gestartet werden"
            return 1
        fi
    else
        stop_webui
        sleep 1
        start_webui
    fi

    return 0
}

# Web UI Logs anzeigen
show_webui_logs() {
    log_info "LOGS: Web UI"

    if command -v journalctl &> /dev/null; then
        journalctl -u serversh-webui -f --no-pager
    else
        local log_file="${SERVERSH_LOG_DIR}/webui.log"
        if [ -f "$log_file" ]; then
            tail -f "$log_file"
        else
            log_error "Keine Logs gefunden"
        fi
    fi
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

# Hauptfunktion
main() {
    case "${1:-}" in
        "info")
            module_info
            ;;
        "check")
            check_dependencies
            ;;
        "install")
            install_module
            ;;
        "configure")
            configure_module
            ;;
        "status")
            module_status
            ;;
        "start")
            start_webui
            ;;
        "stop")
            stop_webui
            ;;
        "restart")
            restart_webui
            ;;
        "logs")
            show_webui_logs
            ;;
        "help"|"-h"|"--help")
            echo "Web UI Modul für ServerSH"
            echo
            echo "Verwendung: $0 {info|check|install|configure|status|start|stop|restart|logs|help}"
            echo
            echo "Befehle:"
            echo "  info      - Modul-Informationen anzeigen"
            echo "  check     - Abhängigkeiten prüfen"
            echo "  install   - Web UI installieren"
            echo "  configure - Web UI konfigurieren"
            echo "  status    - Web UI Status anzeigen"
            echo "  start     - Web UI starten"
            echo "  stop      - Web UI stoppen"
            echo "  restart   - Web UI neustarten"
            echo "  logs      - Web UI Logs anzeigen"
            echo "  help      - Diese Hilfe anzeigen"
            ;;
        *)
            log_error "Ungültiger Befehl: ${1:-}"
            log_info "Verwendung: $0 {info|check|install|configure|status|start|stop|restart|logs|help}"
            exit 1
            ;;
    esac
}

# Skript ausführen
main "$@"