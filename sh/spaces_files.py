#!/usr/bin/env python3
"""
DigitalOcean Spaces SH Script Grid Generator with CDN Purge
Creates a beautiful GitHub-style grid view of all .sh scripts in a DigitalOcean Space
Each script is displayed in an iframe using the SH Preview tool
Includes CDN purge functionality for cache invalidation
"""

import os
import sys
import json
import boto3
import requests
import webbrowser
from datetime import datetime
from botocore.client import Config
from botocore.exceptions import ClientError
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Default configuration
DEFAULT_USERNAME = "https://shbash.netlify.app/"
# DEFAULT_USERNAME = "igiteam"
# DEFAULT_AVATAR = "https://github.com/igiteam.png"
# DEFAULT_GITHUB_URL = "https://igiteam.github.io/"
DEFAULT_AVATAR = "https://cdn.gitgpt.chat/rtx/images/bash.png"
DEFAULT_GITHUB_URL = "https://github.com/igiteam/sh"
OUTPUT_FILE = 'index.html'
OUTPUT_DIRECTORY = 'public'
SH_PREVIEW_URL = "https://igiteam.github.io/sh"
CDN_PURGE_ENDPOINT = "https://api.digitalocean.com/v2/cdn/endpoints"
SUPPORT_URL = "https://buymeacoffee.com/igiteam"
SH_GITHUB_URL = "https://github.com/igiteam/sh"
SH_TERMINAL_URL = "https://igiteam.github.io/sh_terminal"

# Color codes for terminal output
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    CYAN = '\033[96m'
    END = '\033[0m'
    BOLD = '\033[1m'

def print_color(text, color):
    """Print colored text"""
    print(f"{color}{text}{Colors.END}")

def show_settings_menu():
    """Show interactive settings menu at start"""
    print("\n" + "="*60)
    print_color("🚀 DIGITALOCEAN SPACES SH SCRIPT GRID GENERATOR", Colors.HEADER + Colors.BOLD)
    print("="*60)
    print("\n📝 Please configure your DigitalOcean Spaces settings:")
    print()
    
       # Get Spaces credentials
    endpoint = os.getenv('DO_SPACES_ENDPOINT', '')
    if not endpoint:
        endpoint = input("Enter DigitalOcean Spaces Endpoint (e.g., sgp1.digitaloceanspaces.com): ").strip()
        if not endpoint:
            print_color("❌ Endpoint is required!", Colors.RED)
            sys.exit(1)
    else:
        print_color(f"✅ Using endpoint from .env: {endpoint}", Colors.GREEN)
    
    region = os.getenv('DO_SPACES_REGION', '')
    if not region:
        region = input("Enter region (e.g., sgp1): ").strip()
        if not region:
            region = endpoint.split('.')[0]
    else:
        print_color(f"✅ Using region from .env: {region}", Colors.GREEN)
    
    access_key = os.getenv('DO_SPACES_KEY', '')
    if not access_key:
        access_key = input("Enter Access Key: ").strip()
        if not access_key:
            print_color("❌ Access Key is required!", Colors.RED)
            sys.exit(1)
    else:
        print_color(f"✅ Using access key from .env", Colors.GREEN)
    
    secret_key = os.getenv('DO_SPACES_SECRET', '')
    if not secret_key:
        secret_key = input("Enter Secret Key: ").strip()
        if not secret_key:
            print_color("❌ Secret Key is required!", Colors.RED)
            sys.exit(1)
    else:
        print_color(f"✅ Using secret key from .env", Colors.GREEN)
    
    bucket = os.getenv('DO_SPACES_BUCKET', '')
    if not bucket:
        bucket = input("Enter Space/Bucket name: ").strip()
        if not bucket:
            print_color("❌ Space name is required!", Colors.RED)
            sys.exit(1)
    else:
        print_color(f"✅ Using bucket from .env: {bucket}", Colors.GREEN)
    
    folder = os.getenv('DO_SPACES_FOLDER', 'rtx')
    folder_input = input(f"\nEnter folder path to scan for .sh scripts (default: {folder}): ").strip()
    if folder_input:
        folder = folder_input
    else:
        print_color(f"✅ Using folder from .env: {folder}", Colors.GREEN)
    
    # CDN Configuration
    print("\n" + "="*60)
    print_color("🌐 CDN CONFIGURATION (Optional but recommended)", Colors.CYAN + Colors.BOLD)
    print("="*60)
    print("For automatic CDN cache purge after updates:")
    print("1. Create API Token at: https://cloud.digitalocean.com/account/api/tokens")
    print("2. Token needs scopes: cdn:read, cdn:update")
    print()
    
    cdn_endpoint = os.getenv('DO_CDN_ENDPOINT', '')
    if not cdn_endpoint:
        cdn_endpoint_input = input("Enter CDN Endpoint URL (e.g., https://cdn.gitgpt.chat) [optional]: ").strip()
        if cdn_endpoint_input:
            cdn_endpoint = cdn_endpoint_input
    else:
        print_color(f"✅ Using CDN endpoint from .env: {cdn_endpoint}", Colors.GREEN)
    
    api_token = os.getenv('DO_API_TOKEN', '')
    if not api_token and cdn_endpoint:
        api_token_input = input("Enter DigitalOcean API Token (for CDN purge): ").strip()
        if api_token_input:
            api_token = api_token_input
    elif api_token:
        print_color(f"✅ Using API token from .env", Colors.GREEN)
    
    cdn_id = os.getenv('DO_CDN_ID', '')
    if not cdn_id and cdn_endpoint and api_token:
        cdn_id_input = input("Enter CDN Endpoint ID (leave blank to auto-detect): ").strip()
        if cdn_id_input:
            cdn_id = cdn_id_input
    elif cdn_id:
        print_color(f"✅ Using CDN ID from .env: {cdn_id}", Colors.GREEN)
    
    # Get username/display name
    print(f"\n👤 Display name (default: {DEFAULT_USERNAME}):")
    username = input("Enter name: ").strip()
    if not username:
        username = DEFAULT_USERNAME
    
    # Get avatar URL
    print(f"\n🖼️  Avatar image URL (default: {DEFAULT_AVATAR}):")
    avatar = input("Enter URL: ").strip()
    if not avatar:
        avatar = DEFAULT_AVATAR
    
    # Get profile URL
    print(f"\n🔗 Profile URL (default: {DEFAULT_GITHUB_URL}):")
    profile_url = input("Enter URL: ").strip()
    if not profile_url:
        profile_url = DEFAULT_GITHUB_URL
    
    print("\n" + "="*60)
    print_color("✅ Settings saved!", Colors.GREEN)
    print(f"   Endpoint: {endpoint}")
    print(f"   Region: {region}")
    print(f"   Bucket: {bucket}")
    if cdn_endpoint:
        print(f"   CDN: {cdn_endpoint}")
        if api_token:
            print(f"   API Token: {'✅ Set' if api_token else '❌ Not set'}")
            print(f"   CDN ID: {cdn_id or 'Will auto-detect'}")
    print(f"   Folder: {folder or 'root'}")
    print(f"   Username: {username}")
    print("="*60)
    
    return {
        'endpoint': endpoint,
        'region': region,
        'access_key': access_key,
        'secret_key': secret_key,
        'bucket': bucket,
        'cdn_endpoint': cdn_endpoint,
        'api_token': api_token,
        'cdn_id': cdn_id,
        'folder': folder,
        'username': username,
        'avatar': avatar,
        'profile_url': profile_url
    }

def init_spaces_client(settings):
    """Initialize DigitalOcean Spaces client"""
    try:
        session = boto3.session.Session()
        client = session.client(
            's3',
            region_name=settings['region'],
            endpoint_url=f"{settings['endpoint']}",
            aws_access_key_id=settings['access_key'],
            aws_secret_access_key=settings['secret_key'],
            config=Config(signature_version='s3v4')
        )
        return client
    except Exception as e:
        print_color(f"❌ Error initializing Spaces client: {e}", Colors.RED)
        return None

def get_cdn_id(api_token, bucket):
    """Auto-detect CDN ID from DigitalOcean API"""
    try:
        headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json'
        }
        
        response = requests.get('https://api.digitalocean.com/v2/cdn/endpoints', headers=headers)
        
        if response.status_code == 200:
            data = response.json()
            endpoints = data.get('endpoints', [])
            
            # Find endpoint that matches our bucket
            for endpoint in endpoints:
                origin = endpoint.get('origin', '')
                if bucket in origin:
                    return endpoint.get('id')
        return None
    except Exception as e:
        print_color(f"⚠️ Error detecting CDN ID: {e}", Colors.YELLOW)
        return None

def purge_cdn_cache(settings, file_paths):
    """Purge CDN cache for specific files"""
    if not settings.get('api_token'):
        return False
    
    cdn_id = settings.get('cdn_id')
    
    # Auto-detect CDN ID if not provided
    if not cdn_id and settings.get('api_token'):
        print_color("🔍 Auto-detecting CDN ID...", Colors.CYAN)
        cdn_id = get_cdn_id(settings['api_token'], settings['bucket'])
        if cdn_id:
            settings['cdn_id'] = cdn_id
            print_color(f"✅ CDN ID detected: {cdn_id}", Colors.GREEN)
    
    if not cdn_id:
        print_color("⚠️ No CDN ID available, skipping cache purge", Colors.YELLOW)
        return False
    
    try:
        headers = {
            'Authorization': f'Bearer {settings["api_token"]}',
            'Content-Type': 'application/json'
        }
        
        # Prepare purge payload
        payload = {
            'files': file_paths
        }
        
        url = f"{CDN_PURGE_ENDPOINT}/{cdn_id}/cache"
        response = requests.delete(url, headers=headers, json=payload)
        
        if response.status_code == 204:
            print_color(f"✅ CDN cache purged for {len(file_paths)} file(s)", Colors.GREEN)
            return True
        else:
            print_color(f"⚠️ CDN purge failed: {response.status_code} - {response.text}", Colors.YELLOW)
            return False
            
    except Exception as e:
        print_color(f"⚠️ Error purging CDN cache: {e}", Colors.YELLOW)
        return False

def list_sh_scripts(client, settings):
    """List all .sh scripts in the specified folder"""
    print_color("\n📋 Scanning for .sh scripts...", Colors.BLUE)
    
    try:
        prefix = settings['folder'] if settings['folder'] else ''
        if prefix and not prefix.endswith('/'):
            prefix += '/'
        
        paginator = client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=settings['bucket'], Prefix=prefix)
        
        scripts = []
        file_paths = []  # For CDN purge
        
        for page in pages:
            if 'Contents' in page:
                for obj in page['Contents']:
                    key = obj['Key']
                    if key.endswith('.sh'):
                        file_paths.append(f"/{key}")
                        
                        # Get public URL
                        public_url = f"https://{settings['bucket']}.{settings['endpoint']}/{key}"
                        
                        # Use CDN URL if available
                        if settings.get('cdn_endpoint'):
                            public_url = f"{settings['cdn_endpoint']}/{key}"
                        
                        # Get file info
                        scripts.append({
                            'name': os.path.basename(key),
                            'path': key,
                            'url': public_url,
                            'preview_url': f"{SH_PREVIEW_URL}?url={public_url}",
                            'edit_url': f"{SH_PREVIEW_URL}?url={public_url}&e=1",
                            'size': obj['Size'],
                            'last_modified': obj['LastModified'].isoformat(),
                            'etag': obj['ETag'].strip('"')
                        })
        
        print_color(f"✨ Found {len(scripts)} .sh script(s)", Colors.GREEN)
        
        # Ask if user wants to purge CDN cache
        if scripts and settings.get('cdn_endpoint') and settings.get('api_token'):
            print()
            response = input(f"{Colors.BOLD}Purge CDN cache for all scripts? (y/N): {Colors.END}").lower()
            if response != '' or response == 'y':
                purge_cdn_cache(settings, file_paths)
        
        return scripts
        
    except ClientError as e:
        print_color(f"❌ Error listing objects: {e}", Colors.RED)
        return []
    except Exception as e:
        print_color(f"❌ Unexpected error: {e}", Colors.RED)
        return []

def format_file_size(size_bytes):
    """Format file size in human readable format"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} TB"

def generate_html_grid(scripts, settings):
    """Generate GitHub-style HTML grid view of SH scripts with iframes"""
    
    scripts_json = json.dumps(scripts)
    script_cards_html = ""
    
    for script in scripts:
        script_cards_html += f'''
            <div class="script-item">
                <div class="iframe-container">
                    <iframe 
                        src="{script['preview_url']}" 
                        style="width: 100%; height: 500px; border: none; background: #1e1e1e;"
                        title="{script['name']}"
                        loading="lazy"
                    ></iframe>
                </div>
                <div class="script-content">
                    <div class="script-title" style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap;">
                        <a href="{script['preview_url']}" target="_blank" style="flex: 0 1 auto;">{script['name']}</a>
                        <a href="{script['edit_url']}" target="_blank" style="flex: 0 1 auto;">
                            <i class="fas fa-code"></i>
                        </a>
                    </div>
                    
                    <div class="script-details">
                        <div style="margin-bottom: 6px; display: flex; align-items: center; gap: 8px;">
                            <i class="fas fa-database" style="width: 16px; color: var(--github-primary);"></i>
                            <span>Size: {format_file_size(script['size'])}</span>
                        </div>
                        <div style="margin-bottom: 6px; display: flex; align-items: center; gap: 8px;">
                            <i class="fas fa-folder" style="width: 16px; color: var(--github-green);"></i>
                            <span>Path: {script['path']}</span>
                        </div>
                        <div style="margin-bottom: 6px; display: flex; align-items: center; gap: 8px;">
                            <i class="fas fa-clock" style="width: 16px; color: var(--github-text-secondary);"></i>
                            <span>Modified: {script['last_modified'][:10]}</span>
                        </div>
                    </div>
                </div>
            </div>
        '''
    
    # CDN info for footer
    cdn_info = ""
    if settings.get('cdn_endpoint'):
        cdn_info = f" | CDN: {settings['cdn_endpoint']}"
    
    html_template = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ShBash Scripts Collection</title>
    <link rel="icon" href="{settings['avatar']}" type="image/x-icon">
    <link rel="apple-touch-icon" href="{settings['avatar']}">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
        }}
        
        :root {{
            --github-bg: #ffffff;
            --github-text: #24292f;
            --github-text-secondary: #57606a;
            --github-border: #d0d7de;
            --github-primary: #0969da;
            --github-green: #1a7f37;
            --github-hover: #f6f8fa;
            --github-shadow: rgba(140, 149, 159, 0.15);
        }}
        
        body {{
            background-color: var(--github-bg);
            color: var(--github-text);
            line-height: 1.5;
            padding: 24px;
        }}
        
        .container {{
            max-width: 1400px;
            margin: 0 auto;
        }}
        
        /* Header */
        .header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 24px;
            padding-bottom: 16px;
            border-bottom: 1px solid var(--github-border);
            flex-wrap: wrap;
            gap: 16px;
        }}
        
        .user-info {{
            display: flex;
            align-items: center;
            gap: 12px;
        }}
        
        .user-avatar {{
            width: 40px;
            height: 40px;
            border-radius: 4px;
            border: 1px solid var(--github-border);
        }}
        
        .user-details {{
            display: flex;
            flex-direction: column;
        }}
        
        .user-name {{
            font-weight: 600;
            font-size: 20px;
            text-decoration: none;
            color: var(--github-text);
        }}
        
        .script-count {{
            font-size: 14px;
            color: var(--github-text-secondary);
        }}
        
        .cdn-badge {{
            font-size: 12px;
            background: var(--github-hover);
            padding: 2px 8px;
            border-radius: 12px;
            color: var(--github-primary);
            display: inline-flex;
            align-items: center;
            gap: 4px;
            margin-left: 8px;
        }}
        
        .cdn-badge i {{
            font-size: 10px;
        }}
        
        .search-container {{
            display: flex;
            gap: 12px;
            align-items: center;
            flex-wrap: wrap;
        }}
        
        .search-input {{
            background-color: var(--github-bg);
            border: 1px solid var(--github-border);
            border-radius: 6px;
            padding: 10px 12px;
            color: var(--github-text);
            font-size: 14px;
            width: 300px;
            transition: all 0.2s;
        }}
        
        .search-input:focus {{
            outline: none;
            border-color: var(--github-primary);
            box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.15);
        }}
        
        .purge-btn {{
            background: var(--github-hover);
            border: 1px solid var(--github-border);
            border-radius: 6px;
            padding: 8px 12px;
            cursor: pointer;
            color: var(--github-text-secondary);
            font-size: 13px;
            display: flex;
            align-items: center;
            gap: 6px;
            transition: all 0.2s;
        }}
        
        .purge-btn:hover {{
            background: var(--github-primary);
            border-color: var(--github-primary);
            color: white;
        }}
        
        .purge-btn i {{
            font-size: 12px;
        }}
        
        /* Script Grid */
        .script-grid {{
            display: grid;
            gap: 24px;
            grid-template-columns: repeat(auto-fill, minmax(450px, 1fr));
            margin-bottom: 40px;
        }}
        
        .script-item {{
            border: 1px solid var(--github-border);
            border-radius: 8px;
            background-color: var(--github-bg);
            overflow: hidden;
            transition: all 0.2s;
            box-shadow: 0 1px 3px var(--github-shadow);
            display: flex;
            flex-direction: column;
        }}
        
        .script-item:hover {{
            border-color: var(--github-primary);
            box-shadow: 0 4px 8px var(--github-shadow);
            transform: translateY(-2px);
        }}
        
        .iframe-container {{
            width: 100%;
            height: 300px;
            overflow: hidden;
            background: #1e1e1e;
            border-bottom: 1px solid var(--github-border);
        }}
        
        .iframe-container iframe {{
            width: 100%;
            height: 100%;
            border: none;
        }}
        
        .script-content {{
            padding: 16px;
            flex: 1;
        }}
        
        .script-title {{
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 12px;
        }}
        
        .script-title a {{
            color: var(--github-primary);
            text-decoration: none;
            font-size: 18px;
            font-weight: 600;
            word-break: break-all;
        }}
        
        .script-title a:hover {{
            text-decoration: underline;
        }}
        
        .script-extension {{
            color: var(--github-text-secondary);
            font-size: 14px;
            font-weight: normal;
        }}
        
        .script-details {{
            margin: 12px 0;
            color: var(--github-text-secondary);
            font-size: 13px;
        }}
        
        .script-actions {{
            display: flex;
            gap: 8px;
            margin-top: 16px;
            padding-top: 12px;
            border-top: 1px solid var(--github-border);
        }}
        
        .action-btn {{
            padding: 8px 16px;
            border-radius: 6px;
            font-size: 13px;
            font-weight: 500;
            text-decoration: none;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            border: 1px solid var(--github-border);
            color: var(--github-text);
            background: var(--github-bg);
        }}
        
        .action-btn:hover {{
            background: var(--github-hover);
            border-color: var(--github-primary);
        }}
        
        .action-btn.primary {{
            background: var(--github-primary);
            border-color: var(--github-primary);
            color: white;
        }}
        
        .action-btn.primary:hover {{
            background: #0a4c9e;
        }}
        
        /* Footer */
        .footer {{
            text-align: center;
            padding: 32px 0;
            border-top: 1px solid var(--github-border);
            color: var(--github-text-secondary);
            font-size: 14px;
        }}
        
        .footer a {{
            color: var(--github-primary);
            text-decoration: none;
        }}
        
        .footer a:hover {{
            text-decoration: underline;
        }}
        
        .footer .cdn-info {{
            font-size: 12px;
            margin-top: 8px;
            color: var(--github-text-secondary);
        }}
        
        /* Loading & Empty States */
        .loading, .no-results {{
            grid-column: 1 / -1;
            text-align: center;
            padding: 60px 20px;
            background: var(--github-hover);
            border: 1px solid var(--github-border);
            border-radius: 8px;
            color: var(--github-text-secondary);
        }}
        
        .loading i {{
            font-size: 32px;
            margin-bottom: 16px;
            color: var(--github-primary);
        }}
        
        /* Toast notification */
        .toast {{
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: #2d2d30;
            color: white;
            padding: 12px 24px;
            border-radius: 30px;
            font-size: 14px;
            z-index: 1000;
            border: 1px solid #3e3e42;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            display: none;
        }}
        
        .toast.show {{
            display: block;
        }}
        
        /* Responsive */
        @media (max-width: 768px) {{
            body {{
                padding: 16px;
            }}
            
            .header {{
                flex-direction: column;
                align-items: flex-start;
            }}
            
            .search-container {{
                width: 100%;
            }}
            
            .search-input {{
                width: 100%;
            }}
            
            .script-grid {{
                grid-template-columns: 1fr;
            }}
            
            .iframe-container {{
                height: 250px;
            }}
        }}
        
        
        /* Floating buttons */
        .floating-buttons {{
            position: fixed;
            bottom: 20px;
            right: 30px;
            z-index: 999999;
            display: flex;
            flex-direction: column;
            gap: 10px;
        }}
        
        .float-btn {{
            width: 60px;
            height: 60px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: all 0.3s ease;
        }}
        
        .float-btn:hover {{
            transform: scale(1.1);
        }}
        
        .float-btn img {{
            width: 30px;
            height: 30px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <div class="user-info">
                <img src="{settings['avatar']}" class="user-avatar" alt="Avatar" 
                     onerror="this.src='https://www.digitalocean.com/favicon.ico'">
                <div class="user-details">
                    <div style="display: flex; align-items: center; gap: 8px;">
                        <a href="{settings['profile_url']}" target="_blank" class="user-name">
                            {settings['username']}
                        </a>
                        {'<span class="cdn-badge"><i class="fas fa-cloud"></i> CDN</span>' if settings.get('cdn_endpoint') else ''}
                    </div>
                    <div class="script-count" id="scriptCount">{len(scripts)} scripts</div>
                </div>
            </div>
            
            <div class="search-container">
                <input type="text" class="search-input" placeholder="Find a script..." id="scriptSearch">
                
                <!-- File size filter dropdown -->
                <select class="size-filter" id="sizeFilter" style="background-color: var(--github-bg); border: 1px solid var(--github-border); border-radius: 6px; padding: 10px 12px; color: var(--github-text); font-size: 13px; cursor: pointer; min-width: 120px; outline: none;">
                    <option value="all">All sizes</option>
                    <option value="100KB">&lt; 100 KB</option>
                    <option value="500KB">&lt; 500 KB</option>
                    <option value="1MB" selected>&lt; 1 MB</option>
                    <option value="5MB">&lt; 5 MB</option>
                    <option value="10MB">&lt; 10 MB</option>
                </select>

                <!-- Upload button -->
                <button class="upload-btn" id="uploadBtn" title="Upload new script" style="background: transparent; border: 1px solid var(--github-border); border-radius: 6px; padding: 10px 16px; cursor: pointer; color: white; font-size: 20px; font-weight: 500; display: flex; align-items: center; gap: 6px;">
                ⬆️
                </button>
            </div>
        </div>
        
        <!-- Script Grid -->
        <div class="script-grid" id="scriptsContainer">
            {script_cards_html}
        </div>
        
        <!-- Footer -->
        <div class="footer">
            <p>📜 SH Scripts from DigitalOcean Spaces{cdn_info}</p>
            <p>Generated on {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>
            <div class="cdn-info">
                <i class="fas fa-bolt"></i> Files are cached for 1 hour. Use Purge button to instantly update.
            </div>
        </div>
    </div>
    
    <!-- Floating Buttons -->
    <div class="floating-buttons">
        <div class="float-btn">
            <a href="{SH_TERMINAL_URL}" target="_blank">
                <img src="https://cdn.gitgpt.chat/rtx/images/sh_terminal.png" alt="Sh Terminal">
            </a>
        </div>
        <div class="float-btn">
            <a href="{SH_GITHUB_URL}" target="_blank">
                <img src="https://cdn.gitgpt.chat/rtx/images/github-icon.png" alt="GitHub">
            </a>
        </div>
        <div class="float-btn">
            <a href="{SUPPORT_URL}" target="_blank">
                <img src="https://studio.buymeacoffee.com/assets/img/bmc-meta-new/new/apple-icon-120x120.png" alt="Buy Me a Coffee">
            </a>
        </div>
    </div>
    
    <!-- Toast -->
    <div class="toast" id="toast">Message</div>
    
    <script>
        // Script data
        const scriptsData = {scripts_json};
        const cdnEndpoint = {json.dumps(settings.get('cdn_endpoint'))};
        
        // File size filter
        document.getElementById('sizeFilter').addEventListener('change', (e) => {{
            const sizeLimit = e.target.value;
            const searchQuery = document.getElementById('scriptSearch').value;
            filterScripts(searchQuery, sizeLimit);
        }});

        // Modified filter function to handle both search and size
        function filterScripts(query, sizeLimit = 'all') {{
            const container = document.getElementById('scriptsContainer');
            const scriptCount = document.getElementById('scriptCount');
            
            let filtered = scriptsData;
            
            // Apply search filter
            if (query.trim()) {{
                filtered = filtered.filter(script => 
                    script.name.toLowerCase().includes(query.toLowerCase()) ||
                    script.path.toLowerCase().includes(query.toLowerCase())
                );
            }}
            
            // Apply size filter
            if (sizeLimit !== 'all') {{
                const limitBytes = {{
                    '100KB': 100 * 1024,
                    '500KB': 500 * 1024,
                    '1MB': 1024 * 1024,
                    '5MB': 5 * 1024 * 1024,
                    '10MB': 10 * 1024 * 1024
                }}[sizeLimit];
                
                filtered = filtered.filter(script => script.size <= limitBytes);
            }}
            
            if (filtered.length === 0) {{
                container.innerHTML = `
                    <div class="no-results">
                        <i class="fas fa-search"></i>
                        <p>No scripts found matching your criteria</p>
                        ${{sizeLimit !== 'all' ? '<p style="font-size: 12px; margin-top: 8px;">Try increasing the file size limit</p>' : ''}}
                    </div>
                `;
            }} else {{
                renderScripts(filtered);
            }}
            
            scriptCount.textContent = `${{filtered.length}} script${{filtered.length > 1 ? 's' : ''}}`;
        }}

        // Upload button click handler
        document.getElementById('uploadBtn').addEventListener('click', () => {{
            showToast('📤 Upload feature coming soon!');
            // Here you'll implement the actual upload functionality later
        }});
        
        function renderScripts(scripts) {{
            const container = document.getElementById('scriptsContainer');
            let html = '';
            
            scripts.forEach(script => {{
                html += `
                    <div class="script-item">
                        <div class="iframe-container">
                            <iframe 
                                src="${{script.preview_url}}" 
                                style="width: 100%; height: 500px; border: none; background: #1e1e1e;"
                                title="${{script.name}}"
                                loading="lazy"
                            ></iframe>
                        </div>
                        <div class="script-content">
                            <div class="script-title" style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap;">
                                <a href="${{script.preview_url}}" target="_blank" style="flex: 0 1 auto;">${{script.name}}</a>
                                <a href="${{script.edit_url}}" target="_blank" style="flex: 0 1 auto;">
                                    <i class="fas fa-code"></i>
                                </a>
                            </div>
                            
                            <div class="script-details">
                                <div style="margin-bottom: 6px; display: flex; align-items: center; gap: 8px;">
                                    <i class="fas fa-database" style="width: 16px; color: var(--github-primary);"></i>
                                    <span>Size: ${{formatSize(script.size)}}</span>
                                </div>
                                <div style="margin-bottom: 6px; display: flex; align-items: center; gap: 8px;">
                                    <i class="fas fa-folder" style="width: 16px; color: var(--github-green);"></i>
                                    <span>Path: ${{script.path}}</span>
                                </div>
                                <div style="margin-bottom: 6px; display: flex; align-items: center; gap: 8px;">
                                    <i class="fas fa-clock" style="width: 16px; color: var(--github-text-secondary);"></i>
                                    <span>Modified: ${{script.last_modified.slice(0, 10)}}</span>
                                </div>
                            </div>
                        </div>
                    </div>
                `;
            }});
            
            container.innerHTML = html;
        }}
        
        function formatSize(bytes) {{
            const units = ['B', 'KB', 'MB', 'GB'];
            let size = bytes;
            let unitIndex = 0;
            
            while (size >= 1024 && unitIndex < units.length - 1) {{
                size /= 1024;
                unitIndex++;
            }}
            
            return `${{size.toFixed(1)}} ${{units[unitIndex]}}`;
        }}
        
        function showToast(message) {{
            const toast = document.getElementById('toast');
            toast.textContent = message;
            toast.classList.add('show');
            setTimeout(() => toast.classList.remove('show'), 2000);
        }}
        
        // Purge CDN cache
        async function purgeCache() {{
            if (!cdnEndpoint) return;
            
            const btn = document.getElementById('purgeCacheBtn');
            btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Purging...';
            btn.disabled = true;
            
            try {{
                // Get all file paths
                const files = scriptsData.map(s => '/' + s.path);
                
                const response = await fetch('/api/purge-cdn', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify({{ files: files }})
                }});
                
                const data = await response.json();
                
                if (data.success) {{
                    showToast('✅ CDN cache purged!');
                    // Refresh iframes with timestamp
                    document.querySelectorAll('.iframe-container iframe').forEach(iframe => {{
                        iframe.src = iframe.src.split('?')[0] + '?t=' + Date.now();
                    }});
                }} else {{
                    showToast('❌ Purge failed');
                }}
            }} catch (err) {{
                showToast('❌ Error: ' + err.message);
            }} finally {{
                btn.innerHTML = '<i class="fas fa-bolt"></i> Purge';
                btn.disabled = false;
            }}
        }}
        
        // Setup search
        document.getElementById('scriptSearch').addEventListener('input', (e) => {{
            const sizeFilter = document.getElementById('sizeFilter').value;
            filterScripts(e.target.value, sizeFilter);
        }});
        
        // Auto-apply 1MB filter on page load
        window.addEventListener('load', () => {{
            // Set dropdown to 1MB (it's already selected by default)
            // Trigger filter to apply the 1MB limit
            filterScripts('', '1MB');
        }});

    </script>
</body>
</html>"""
    
    return html_template

def save_html_file(html_content, output_file=OUTPUT_FILE, output_dir=OUTPUT_DIRECTORY):
    """Save HTML content to file"""
    try:
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
            output_path = os.path.join(output_dir, output_file)
        else:
            output_path = output_file
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        print_color(f"✅ HTML file saved: {os.path.abspath(output_path)}", Colors.GREEN)
        return True
        
    except Exception as e:
        print_color(f"❌ Error saving HTML file: {e}", Colors.RED)
        return False

def main():
    """Main function"""
    # Show interactive settings menu
    settings = show_settings_menu()
    
    # Initialize Spaces client
    client = init_spaces_client(settings)
    if not client:
        return
    
    # List .sh scripts
    scripts = list_sh_scripts(client, settings)
    
    if not scripts:
        print_color("❌ No .sh scripts found in the specified folder", Colors.RED)
        return
    
    print_color(f"\n📊 Processing {len(scripts)} scripts...", Colors.BLUE)
    
    # Generate HTML grid
    print_color("🎨 Generating SH script grid view...", Colors.BLUE)
    html_content = generate_html_grid(scripts, settings)
    
    # Save HTML file
    if save_html_file(html_content):
        print_color("\n📊 Grid Summary:", Colors.BOLD)
        print_color(f"   Total scripts: {len(scripts)}", Colors.CYAN)
        print_color(f"   Output file: {OUTPUT_FILE}", Colors.CYAN)
        if settings.get('cdn_endpoint'):
            print_color(f"   CDN: {settings['cdn_endpoint']}", Colors.CYAN)
        
        # Ask if user wants to open the file
        response = input(f"\n{Colors.BOLD}Open HTML file in browser? (y/n): {Colors.END}").lower()
        if response == 'y':
            file_path = os.path.join(OUTPUT_DIRECTORY, OUTPUT_FILE)
            webbrowser.open(f"file://{os.path.abspath(file_path)}")
    
    print_color("\n✨ Done! The SH script grid has been generated.", Colors.GREEN)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print_color("\n\n👋 Operation cancelled by user.", Colors.BLUE)
    except Exception as e:
        print_color(f"\n❌ Unexpected error: {e}", Colors.RED)
        import traceback
        traceback.print_exc()