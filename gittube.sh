#!/bin/bash

# GitHub/Archive Discovery Platform - Digital Ocean Setup v1.0
# Complete discovery server with GitHub API + Archive.org + Media extraction
# Like YouTube but for software discovery!
# Usage: curl -sL https://raw.githubusercontent.com/YOUR_USER/discovery/main/setup.sh | sudo bash

# Force non-interactive mode
export DEBIAN_FRONTEND=noninteractive

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    read -p "$prompt [$default]: " input
    eval "$var_name=\${input:-\$default}"
}

validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Display banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   GitHub/Archive Discovery Platform v1.0                ║"
echo "║   Like YouTube for software discovery!                  ║"
echo "║   + GitHub API + Archive.org + Media extraction         ║"
echo "║   + QUEUE SYSTEM + Trending Analysis                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    warn "Not running as root. Some commands may need sudo."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
fi

# Get configuration
echo ""
info "Please provide configuration details:"
echo "-------------------------------------"


# Function to validate domain format (RFC-compliant)
validate_domain() {
    local domain="$1"
    
    # Remove trailing dot if present
    domain="${domain%.}"
    
    # Check if empty
    if [ -z "$domain" ]; then
        warn "Domain cannot be empty"
        return 1
    fi
    
    # Check length (max 253 characters)
    if [ ${#domain} -gt 253 ]; then
        warn "Domain is too long (max 253 characters)"
        return 1
    fi
    
    # Check for invalid characters
    if [[ "$domain" =~ [^a-zA-Z0-9.-] ]]; then
        warn "Domain contains invalid characters (only letters, numbers, dots, and hyphens allowed)"
        return 1
    fi
    
    # Check if it starts or ends with dot
    if [[ "$domain" == .* ]] || [[ "$domain" == *. ]]; then
        warn "Domain cannot start or end with a dot"
        return 1
    fi
    
    # Check for double dots
    if [[ "$domain" == *..* ]]; then
        warn "Domain cannot contain consecutive dots"
        return 1
    fi
    
    # Check if it's just a single word without TLD
    if [[ ! "$domain" =~ \. ]]; then
        warn "Domain must contain at least one dot (e.g., discover.sdappnet.cloud or sdappnet.cloud)"
        return 1
    fi
    
    # Split into parts and validate each part
    IFS='.' read -ra parts <<< "$domain"
    
    # Check TLD (last part) - must be at least 2 characters
    local tld="${parts[-1]}"
    if [ ${#tld} -lt 2 ]; then
        warn "TLD must be at least 2 characters (e.g., .com, .cloud, .io)"
        return 1
    fi
    
    # Check each part for valid format
    for part in "${parts[@]}"; do
        # Check part length (max 63 characters)
        if [ ${#part} -gt 63 ]; then
            warn "Domain part '$part' is too long (max 63 characters)"
            return 1
        fi
        
        # Check if part starts or ends with hyphen
        if [[ "$part" == -* ]] || [[ "$part" == *- ]]; then
            warn "Domain part '$part' cannot start or end with a hyphen"
            return 1
        fi
        
        # Check if part contains only valid characters
        if [[ ! "$part" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            warn "Domain part '$part' contains invalid characters or format"
            return 1
        fi
    done
    
    # Check for common typos
    local common_tlds="com org net io co uk de fr es it nl ru br au jp cn in"
    if [[ ${#parts[@]} -eq 2 ]] && [[ ! " $common_tlds " =~ " ${tld} " ]]; then
        warn "Warning: Uncommon TLD '$tld'. Make sure this is correct!"
        return 0
    fi
    
    # Check if it's just an IP address (common mistake)
    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "That looks like an IP address, not a domain name"
        return 1
    fi
    
    # All checks passed
    return 0
}

while true; do
    get_input "Enter your MAIN domain (e.g., discover.sdappnet.cloud)" "discover.sdappnet.cloud" DOMAIN_NAME
    
    # Validate domain format
    if validate_domain "$DOMAIN_NAME"; then
        break
    else
        warn "Invalid domain format. Please enter a full domain (e.g., discover.sdappnet.cloud)"
    fi
done

# DON'T MODIFY THE DOMAIN - use exactly what the user entered
info "Using domain: $DOMAIN_NAME"
echo ""

while true; do
    get_input "Enter email for SSL certificate" "admin@$DOMAIN_NAME" SSL_EMAIL
    if validate_email "$SSL_EMAIL"; then
        break
    else
        error "Invalid email format. Please enter a valid email."
    fi
done

# Get droplet IP
DROPLET_IP=$(curl -s --fail ifconfig.me 2>/dev/null || curl -s --fail http://checkip.amazonaws.com 2>/dev/null || echo "UNKNOWN")
info "Detected droplet IP: $DROPLET_IP"

# Get GitHub API key
get_input "Enter GitHub API token (required for higher rate limits)" "your-github-token-here" GITHUB_TOKEN

# Get API key for internal services
get_input "Enter API key for internal services (generate one)" "$(openssl rand -hex 16)" API_KEY

# Queue concurrency setting
get_input "Max concurrent jobs (3-10)" "5" MAX_CONCURRENT

echo ""
log "Starting Discovery Platform Setup..."
log "Domain: $DOMAIN_NAME"
log "Email: $SSL_EMAIL"
log "Droplet IP: $DROPLET_IP"
log "GitHub Token: ${GITHUB_TOKEN:0:8}..."
log "Internal API Key: $API_KEY"
log "Max concurrent jobs: $MAX_CONCURRENT"

# Update system
log "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# Install required tools
log "Installing required tools..."
apt-get install -y -qq curl wget git build-essential python3-pip python3-venv redis-server

# Create swap file (critical for 512MB droplets)
log "Setting up swap space..."
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swap file created (2GB)"
fi

# Install Node.js 18
log "Installing Node.js 18..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y -qq nodejs

# Install PM2
log "Installing PM2..."
npm install -g pm2

# Install Bull Queue dependencies
log "Installing Bull Queue for job processing..."
npm install -g bull

# Create application directory structure
log "Creating application directories..."
mkdir -p /opt/discovery-platform/{api,scripts,logs}
cd /opt/discovery-platform

# ============= PART 1: SETUP ARCHIVE.ORG SERVICE =============
log "Setting up Archive.org service..."

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install fastapi uvicorn redis internetarchive

# Create the Archive.org service
cat > /opt/discovery-platform/api/archive_service.py << 'EOF'
#!/usr/bin/env python3
"""
Archive.org Service - Runs on port 5001
Fetches vintage software from Archive.org with screenshots
"""

import os
import time
import json
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel
import uvicorn
from internetarchive import get_item, search_items

app = FastAPI(title="Archive.org Service")

API_KEY = os.environ.get('API_KEY', 'your-api-key-here')

class ArchiveRequest(BaseModel):
    query: str
    max_items: int = 10
    collections: List[str] = []
    include_screenshots: bool = True

class ArchiveResponse(BaseModel):
    items: List[dict]
    total: int
    time_ms: float

def verify_api_key(authorization: str = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="No API key provided")
    
    if authorization.startswith("Bearer "):
        token = authorization[7:]
    else:
        token = authorization
    
    if token != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    return token

def get_screenshots(identifier):
    """Extract screenshot URLs from an Archive.org item"""
    screenshots = []
    try:
        item = get_item(identifier)
        if item.files:
            for file in item.files:
                name = file.get('name', '')
                if name.lower().endswith(('.png', '.jpg', '.jpeg', '.gif')):
                    if ('screenshot' in name.lower() or 
                        'screen' in name.lower() or 
                        'shot' in name.lower() or
                        'preview' in name.lower()):
                        screenshots.append({
                            'name': name,
                            'url': f"https://archive.org/download/{identifier}/{name}",
                            'size': file.get('size')
                        })
        
        # Add thumbnail as fallback
        if not screenshots:
            screenshots.append({
                'name': 'thumbnail',
                'url': f"https://archive.org/services/img/{identifier}"
            })
    except Exception as e:
        print(f"Error getting screenshots for {identifier}: {e}")
    
    return screenshots[:3]  # Limit to 3 screenshots

def build_collection_query(collections):
    """Build query string from collections list"""
    if not collections:
        return ""
    collection_terms = [f"collection:{c}" for c in collections]
    return " AND (" + " OR ".join(collection_terms) + ")"

@app.post("/v1/archive/search", response_model=ArchiveResponse)
async def search_archive(
    request: ArchiveRequest,
    api_key: str = Depends(verify_api_key)
):
    start_time = time.time()
    
    # Build the query
    query = request.query
    if request.collections:
        query += build_collection_query(request.collections)
    
    print(f"Searching Archive.org: {query}")
    
    try:
        # Search Archive.org
        search = search_items(
            query, 
            params={'rows': request.max_items}
        )
        
        items = []
        for item in search:
            try:
                # Get full item details
                item_detail = get_item(item['identifier'])
                
                # Build item data
                feed_item = {
                    'id': f"archive:{item['identifier']}",
                    'type': 'vintage-software',
                    'identifier': item['identifier'],
                    'title': item.get('title', 'Unknown'),
                    'description': str(item.get('description', ''))[:300],
                    'year': item.get('year'),
                    'creator': item.get('creator', 'Unknown'),
                    'downloads': item.get('downloads', 0),
                    'source': 'archive.org',
                    'url': f"https://archive.org/details/{item['identifier']}",
                    'fetched_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
                }
                
                # Add screenshots if requested
                if request.include_screenshots:
                    feed_item['screenshots'] = get_screenshots(item['identifier'])
                
                items.append(feed_item)
                
            except Exception as e:
                print(f"Error processing {item.get('identifier', 'unknown')}: {e}")
                continue
        
        elapsed = (time.time() - start_time) * 1000
        
        return ArchiveResponse(
            items=items,
            total=len(items),
            time_ms=round(elapsed, 2)
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/v1/archive/item/{identifier}")
async def get_archive_item(
    identifier: str,
    api_key: str = Depends(verify_api_key)
):
    start_time = time.time()
    
    try:
        item = get_item(identifier)
        metadata = item.metadata
        
        # Get screenshots
        screenshots = get_screenshots(identifier)
        
        # Build response
        result = {
            'id': f"archive:{identifier}",
            'type': 'vintage-software',
            'identifier': identifier,
            'title': metadata.get('title', ['Unknown'])[0],
            'description': str(metadata.get('description', [''])[0])[:500],
            'year': metadata.get('year', [''])[0],
            'creator': metadata.get('creator', ['Unknown'])[0],
            'publisher': metadata.get('publisher', [''])[0],
            'downloads': metadata.get('downloads', [0])[0],
            'screenshots': screenshots,
            'files': [
                {'name': f.get('name'), 'size': f.get('size')}
                for f in item.files[:10] if f.get('name')
            ] if item.files else [],
            'url': f"https://archive.org/details/{identifier}",
            'fetched_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'time_ms': round((time.time() - start_time) * 1000, 2)
        }
        
        return result
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "archive.org",
        "timestamp": time.time()
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5001)
EOF

# ============= PART 2: SETUP GITHUB SERVICE =============
log "Setting up GitHub service..."

cat > /opt/discovery-platform/api/github_service.py << 'EOF'
#!/usr/bin/env python3
"""
GitHub Service - Runs on port 5002
Fetches GitHub repos with README media extraction
"""

import os
import time
import re
import base64
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel
import uvicorn
import httpx

app = FastAPI(title="GitHub Service")

API_KEY = os.environ.get('API_KEY', 'your-api-key-here')
GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN', '')

HEADERS = {
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'Discovery-Platform/1.0'
}
if GITHUB_TOKEN:
    HEADERS['Authorization'] = f'token {GITHUB_TOKEN}'

class GitHubRequest(BaseModel):
    repos: List[str]
    extract_media: bool = True
    include_readme: bool = True

class GitHubResponse(BaseModel):
    items: List[dict]
    errors: List[dict]
    total: int
    time_ms: float

def verify_api_key(authorization: str = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="No API key provided")
    
    if authorization.startswith("Bearer "):
        token = authorization[7:]
    else:
        token = authorization
    
    if token != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    return token

def extract_youtube(text):
    """Extract YouTube video IDs from text"""
    youtube_patterns = [
        r'(?:https?:\/\/)?(?:www\.)?youtube\.com\/watch\?v=([a-zA-Z0-9_-]+)',
        r'(?:https?:\/\/)?youtu\.be\/([a-zA-Z0-9_-]+)',
        r'(?:https?:\/\/)?(?:www\.)?youtube\.com\/embed\/([a-zA-Z0-9_-]+)'
    ]
    
    videos = []
    for pattern in youtube_patterns:
        matches = re.findall(pattern, text)
        for match in matches:
            video_id = match
            if isinstance(match, tuple):
                video_id = match[0]
            videos.append({
                'id': video_id,
                'url': f'https://www.youtube.com/watch?v={video_id}',
                'embed': f'https://www.youtube.com/embed/{video_id}',
                'thumbnail': f'https://img.youtube.com/vi/{video_id}/hqdefault.jpg'
            })
    
    # Remove duplicates
    seen = set()
    unique_videos = []
    for v in videos:
        if v['id'] not in seen:
            seen.add(v['id'])
            unique_videos.append(v)
    
    return unique_videos[:3]  # Limit to 3 videos

def extract_images(text):
    """Extract image URLs from markdown/text"""
    images = []
    
    # Markdown images: ![alt](url)
    md_images = re.findall(r'!\[.*?\]\((.*?)\)', text)
    for url in md_images:
        if not any(bad in url.lower() for bad in ['badge', 'shields.io', 'travis']):
            images.append({
                'url': url,
                'type': 'markdown'
            })
    
    # HTML images: <img src="url">
    html_images = re.findall(r'<img.*?src=["\'](.*?)["\']', text)
    for url in html_images:
        if not any(bad in url.lower() for bad in ['badge', 'shields.io']):
            images.append({
                'url': url,
                'type': 'html'
            })
    
    return images[:5]  # Limit to 5 images

def find_cover_image(images, videos):
    """Find the best cover image (video thumbnail > gif > png/jpg)"""
    # Prefer YouTube thumbnails
    if videos:
        return {
            'type': 'youtube',
            'url': videos[0]['thumbnail'],
            'video_id': videos[0]['id']
        }
    
    # Then look for GIFs
    for img in images:
        if img['url'].lower().endswith('.gif'):
            return {
                'type': 'gif',
                'url': img['url']
            }
    
    # Then any image
    if images:
        return {
            'type': 'image',
            'url': images[0]['url']
        }
    
    return None

async def fetch_repo(repo_full_name):
    """Fetch repository data from GitHub API"""
    async with httpx.AsyncClient() as client:
        # Get repo info
        repo_resp = await client.get(
            f'https://api.github.com/repos/{repo_full_name}',
            headers=HEADERS,
            timeout=10.0
        )
        
        if repo_resp.status_code != 200:
            return {
                'error': f'GitHub API error: {repo_resp.status_code}',
                'repo': repo_full_name
            }
        
        repo_data = repo_resp.json()
        
        result = {
            'repo': repo_full_name,
            'name': repo_data['name'],
            'full_name': repo_data['full_name'],
            'description': repo_data['description'],
            'stars': repo_data['stargazers_count'],
            'forks': repo_data['forks_count'],
            'language': repo_data['language'],
            'topics': repo_data.get('topics', []),
            'created_at': repo_data['created_at'],
            'updated_at': repo_data['updated_at'],
            'html_url': repo_data['html_url'],
            'homepage': repo_data.get('homepage'),
            'owner': {
                'login': repo_data['owner']['login'],
                'avatar_url': repo_data['owner']['avatar_url']
            }
        }
        
        # Get README if requested
        readme_resp = await client.get(
            f'https://api.github.com/repos/{repo_full_name}/readme',
            headers={**HEADERS, 'Accept': 'application/vnd.github.v3.raw'},
            timeout=10.0
        )
        
        if readme_resp.status_code == 200:
            readme_content = readme_resp.text
            
            # Extract media from README
            videos = extract_youtube(readme_content)
            images = extract_images(readme_content)
            cover = find_cover_image(images, videos)
            
            result['media'] = {
                'videos': videos,
                'images': images,
                'cover': cover,
                'has_media': len(videos) > 0 or len(images) > 0
            }
            
            # Include truncated README if requested
            result['readme_preview'] = readme_content[:500] + '...'
        
        return result

@app.post("/v1/github/fetch", response_model=GitHubResponse)
async def fetch_repos(
    request: GitHubRequest,
    api_key: str = Depends(verify_api_key)
):
    start_time = time.time()
    
    results = []
    errors = []
    
    for repo in request.repos:
        try:
            result = await fetch_repo(repo)
            if 'error' in result:
                errors.append(result)
            else:
                results.append(result)
        except Exception as e:
            errors.append({
                'repo': repo,
                'error': str(e)
            })
    
    elapsed = (time.time() - start_time) * 1000
    
    return GitHubResponse(
        items=results,
        errors=errors,
        total=len(results),
        time_ms=round(elapsed, 2)
    )

@app.get("/v1/github/trending")
async def get_trending(
    language: str = None,
    since: str = 'daily',
    api_key: str = Depends(verify_api_key)
):
    """Get trending repositories (simulated via GitHub search)"""
    start_time = time.time()
    
    # Build query
    date_ranges = {
        'daily': '>=' + time.strftime('%Y-%m-%d', time.gmtime(time.time() - 86400)),
        'weekly': '>=' + time.strftime('%Y-%m-%d', time.gmtime(time.time() - 604800)),
        'monthly': '>=' + time.strftime('%Y-%m-%d', time.gmtime(time.time() - 2592000))
    }
    
    date_filter = date_ranges.get(since, date_ranges['daily'])
    query = f'pushed:{date_filter} stars:>100'
    
    if language:
        query += f' language:{language}'
    
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            'https://api.github.com/search/repositories',
            params={
                'q': query,
                'sort': 'stars',
                'order': 'desc',
                'per_page': 25
            },
            headers=HEADERS,
            timeout=10.0
        )
        
        if resp.status_code != 200:
            raise HTTPException(status_code=500, detail='GitHub API error')
        
        data = resp.json()
        
        # Format results
        items = []
        for repo in data.get('items', []):
            items.append({
                'repo': repo['full_name'],
                'name': repo['name'],
                'description': repo['description'],
                'stars': repo['stargazers_count'],
                'language': repo['language'],
                'url': repo['html_url'],
                'avatar': repo['owner']['avatar_url']
            })
        
        return {
            'items': items,
            'total': len(items),
            'since': since,
            'language': language,
            'time_ms': round((time.time() - start_time) * 1000, 2)
        }

@app.get("/v1/github/search")
async def search_repos(
    q: str,
    sort: str = 'stars',
    order: str = 'desc',
    per_page: int = 10,
    api_key: str = Depends(verify_api_key)
):
    """Search GitHub repositories"""
    start_time = time.time()
    
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            'https://api.github.com/search/repositories',
            params={
                'q': q,
                'sort': sort,
                'order': order,
                'per_page': per_page
            },
            headers=HEADERS,
            timeout=10.0
        )
        
        if resp.status_code != 200:
            raise HTTPException(status_code=500, detail='GitHub API error')
        
        data = resp.json()
        
        items = []
        for repo in data.get('items', []):
            items.append({
                'repo': repo['full_name'],
                'name': repo['name'],
                'description': repo['description'],
                'stars': repo['stargazers_count'],
                'language': repo['language'],
                'url': repo['html_url']
            })
        
        return {
            'items': items,
            'total_count': data.get('total_count', 0),
            'time_ms': round((time.time() - start_time) * 1000, 2)
        }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "github",
        "timestamp": time.time()
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5002)
EOF

# ============= PART 3: SETUP API GATEWAY WITH QUEUE =============
log "Setting up API Gateway with QUEUE system..."

cat > /opt/discovery-platform/api/gateway.js << 'EOF'
const express = require('express');
const axios = require('axios');
const Redis = require('ioredis');
const crypto = require('crypto');
const Queue = require('bull');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || '${API_KEY}';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || '${GITHUB_TOKEN}';
const MAX_CONCURRENT = parseInt(process.env.MAX_CONCURRENT) || 5;

// Redis for caching
const redis = new Redis({
    host: 'localhost',
    port: 6379,
    retryStrategy: (times) => Math.min(times * 50, 2000)
});

// ============= QUEUE SYSTEMS =============
// Queue for repo processing
const repoQueue = new Queue('repo processing', {
    redis: { host: 'localhost', port: 6379 },
    defaultJobOptions: {
        attempts: 2,
        backoff: { type: 'exponential', delay: 2000 },
        timeout: 60000,
        removeOnComplete: true,
        removeOnFail: false
    }
});

// Queue for analysis (trending, recommendations)
const analysisQueue = new Queue('analysis processing', {
    redis: { host: 'localhost', port: 6379 },
    defaultJobOptions: {
        attempts: 1,
        timeout: 120000,
        removeOnComplete: true,
        removeOnFail: false
    }
});

// Process repo jobs
repoQueue.process(MAX_CONCURRENT, async (job) => {
    const { repos, extractMedia, jobId } = job.data;
    
    console.log(`[Queue:${jobId}] Processing ${repos.length} repos (Job ${job.id})`);
    
    // Call GitHub service
    const githubResponse = await axios.post('http://localhost:5002/v1/github/fetch', {
        repos: repos,
        extract_media: extractMedia !== false
    }, {
        timeout: 60000,
        headers: { 'Authorization': API_KEY }
    });
    
    return {
        ...githubResponse.data,
        stats: {
            ...githubResponse.data,
            processing_time_ms: Date.now() - job.data.timestamp
        }
    };
});

// Process analysis jobs
analysisQueue.process(2, async (job) => {
    const { type, params, jobId } = job.data;
    
    console.log(`[Analysis:${jobId}] ${type} analysis`);
    
    if (type === 'trending') {
        const response = await axios.get('http://localhost:5002/v1/github/trending', {
            params: params,
            headers: { 'Authorization': API_KEY }
        });
        return response.data;
    }
    
    if (type === 'search') {
        const response = await axios.get('http://localhost:5002/v1/github/search', {
            params: params,
            headers: { 'Authorization': API_KEY }
        });
        return response.data;
    }
    
    if (type === 'archive') {
        const response = await axios.post('http://localhost:5001/v1/archive/search', params, {
            headers: { 'Authorization': API_KEY }
        });
        return response.data;
    }
    
    throw new Error(`Unknown analysis type: ${type}`);
});

// Queue stats endpoint
app.get('/queue/stats', async (req, res) => {
    const [repoWaiting, repoActive, repoCompleted, repoFailed, 
           analysisWaiting, analysisActive, analysisCompleted, analysisFailed] = await Promise.all([
        repoQueue.getWaitingCount(), repoQueue.getActiveCount(), 
        repoQueue.getCompletedCount(), repoQueue.getFailedCount(),
        analysisQueue.getWaitingCount(), analysisQueue.getActiveCount(),
        analysisQueue.getCompletedCount(), analysisQueue.getFailedCount()
    ]);
    
    res.json({
        repo: {
            waiting: repoWaiting,
            active: repoActive,
            completed: repoCompleted,
            failed: repoFailed,
            concurrency: MAX_CONCURRENT
        },
        analysis: {
            waiting: analysisWaiting,
            active: analysisActive,
            completed: analysisCompleted,
            failed: analysisFailed,
            concurrency: 2
        }
    });
});

app.use(express.json());

// ============= DISCOVERY ENDPOINTS =============
// Main discovery endpoint: /?repo=user/repo&repo=user/repo2
app.get('/', async (req, res) => {
    const startTime = Date.now();
    
    try {
        // Handle both single and multiple repos
        const repoParams = req.query.repo;
        const forceRefresh = req.query.recache === '1' || req.query.rc === '1';
        const extractMedia = req.query.media !== 'false';
        const includeArchive = req.query.archive === '1';
        
        // Convert to array
        const repos = Array.isArray(repoParams) ? repoParams : [repoParams];
        
        // Filter out empty/invalid repos
        const validRepos = repos.filter(r => r && r.trim() !== '');
        
        if (validRepos.length === 0) {
            return res.status(400).json({ 
                error: 'Missing repo parameter',
                example: 'https://discover.domain/?repo=blender/blender&repo=microsoft/vscode'
            });
        }

        // Generate cache key
        const cacheKeyBase = validRepos.sort().join('|');
        const cacheKey = crypto.createHash('md5')
            .update(cacheKeyBase + (includeArchive ? ':archive' : ''))
            .digest('hex');
        
        // CHECK CACHE
        if (!forceRefresh) {
            try {
                const cached = await redis.get(`discover:${cacheKey}`);
                if (cached) {
                    const cachedData = JSON.parse(cached);
                    console.log(`[Cache] HIT for ${validRepos.length} repos`);
                    
                    res.set('X-Cache', 'HIT');
                    res.set('X-Processing-Time', `${Date.now() - startTime}ms`);
                    res.set('Content-Type', 'application/json');
                    
                    return res.json({
                        ...cachedData,
                        cached: true,
                        cached_at: cachedData.generated_at
                    });
                }
            } catch (err) {
                console.log(`[Cache] Read error: ${err.message}`);
            }
        }

        console.log(`[Cache] MISS for ${validRepos.length} repos, queueing...`);

        // Check queue load
        const repoWaiting = await repoQueue.getWaitingCount();
        
        if (repoWaiting > 50) {
            return res.status(503).json({
                error: 'Queue is full',
                queue: { waiting: repoWaiting },
                retryAfter: Math.ceil(repoWaiting / MAX_CONCURRENT) * 10,
                message: 'Too many requests. Please try again in a few seconds.'
            });
        }
        
        // Create job ID
        const jobId = uuidv4().substring(0, 8);
        
        // Add to queue
        const job = await repoQueue.add({
            repos: validRepos,
            extractMedia,
            timestamp: Date.now(),
            jobId
        }, {
            jobId: `repo-${jobId}-${Date.now()}`
        });
        
        console.log(`[Queue] Added repo job ${job.id} (${jobId}) for ${validRepos.length} repos`);
        
        // Wait for job to complete
        const result = await job.finished();
        
        console.log(`[Queue] Job ${job.id} completed in ${Date.now() - startTime}ms`);
        
        // Prepare response
        const responseData = {
            request: {
                repos: validRepos,
                total: validRepos.length,
                generated_at: new Date().toISOString(),
                force_refresh: forceRefresh,
                extract_media: extractMedia
            },
            ...result,
            stats: {
                ...result.stats,
                total_time_ms: Date.now() - startTime,
                queue_waiting: repoWaiting,
                cache_key: cacheKey
            }
        };
        
        // Add archive items if requested
        if (includeArchive) {
            try {
                const archiveResponse = await axios.post('http://localhost:5001/v1/archive/search', {
                    query: validRepos.map(r => r.split('/')[1] || r).join(' '),
                    max_items: 5,
                    collections: ['softwarelibrary_msdos', 'softwarelibrary_win95', 'cdrom-software']
                }, {
                    headers: { 'Authorization': API_KEY }
                });
                
                responseData.vintage = archiveResponse.data.items;
            } catch (err) {
                console.log(`[Archive] Error: ${err.message}`);
            }
        }
        
        // Store in cache (1 hour)
        try {
            await redis.setex(
                `discover:${cacheKey}`, 
                3600,
                JSON.stringify(responseData)
            );
            console.log(`[Cache] Stored result for ${cacheKey}`);
        } catch (err) {
            console.log(`[Cache] Store error: ${err.message}`);
        }
        
        // Return response
        res.set('X-Cache', 'MISS');
        res.set('X-Processing-Time', `${Date.now() - startTime}ms`);
        res.set('X-Queue-Position', repoWaiting + 1);
        res.set('Content-Type', 'application/json');
        
        res.json(responseData);

    } catch (error) {
        console.error(`[Error] ${error.message}`);
        res.status(500).json({
            error: 'Failed to process request',
            details: error.message,
            repos: req.query.repo
        });
    }
});

// Trending endpoint
app.get('/trending', async (req, res) => {
    const startTime = Date.now();
    
    try {
        const { language, since = 'daily' } = req.query;
        
        const cacheKey = `trending:${language || 'all'}:${since}`;
        
        // Check cache
        const cached = await redis.get(cacheKey);
        if (cached) {
            res.set('X-Cache', 'HIT');
            return res.json(JSON.parse(cached));
        }
        
        // Call GitHub service
        const response = await axios.get('http://localhost:5002/v1/github/trending', {
            params: { language, since },
            headers: { 'Authorization': API_KEY }
        });
        
        const result = {
            ...response.data,
            generated_at: new Date().toISOString(),
            time_ms: Date.now() - startTime
        };
        
        // Cache for 1 hour
        await redis.setex(cacheKey, 3600, JSON.stringify(result));
        
        res.set('X-Cache', 'MISS');
        res.json(result);
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Search endpoint
app.get('/search', async (req, res) => {
    const startTime = Date.now();
    
    try {
        const { q, sort = 'stars', order = 'desc', per_page = 20 } = req.query;
        
        if (!q) {
            return res.status(400).json({ error: 'Missing search query' });
        }
        
        const cacheKey = `search:${q}:${sort}:${order}:${per_page}`;
        
        // Check cache (15 minutes for search)
        const cached = await redis.get(cacheKey);
        if (cached) {
            res.set('X-Cache', 'HIT');
            return res.json(JSON.parse(cached));
        }
        
        // Call GitHub service
        const response = await axios.get('http://localhost:5002/v1/github/search', {
            params: { q, sort, order, per_page },
            headers: { 'Authorization': API_KEY }
        });
        
        const result = {
            ...response.data,
            query: q,
            generated_at: new Date().toISOString(),
            time_ms: Date.now() - startTime
        };
        
        // Cache for 15 minutes
        await redis.setex(cacheKey, 900, JSON.stringify(result));
        
        res.set('X-Cache', 'MISS');
        res.json(result);
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Archive search endpoint
app.get('/archive', async (req, res) => {
    const startTime = Date.now();
    
    try {
        const { q, collection, year, limit = 20 } = req.query;
        
        if (!q && !collection) {
            return res.status(400).json({ error: 'Missing search query or collection' });
        }
        
        // Build query
        let query = q || '';
        if (collection) {
            query += ` collection:${collection}`;
        }
        if (year) {
            query += ` year:${year}`;
        }
        
        const cacheKey = `archive:${query}:${limit}`;
        
        // Check cache (1 hour)
        const cached = await redis.get(cacheKey);
        if (cached) {
            res.set('X-Cache', 'HIT');
            return res.json(JSON.parse(cached));
        }
        
        // Call Archive service
        const response = await axios.post('http://localhost:5001/v1/archive/search', {
            query: query,
            max_items: parseInt(limit),
            include_screenshots: true
        }, {
            headers: { 'Authorization': API_KEY }
        });
        
        const result = {
            ...response.data,
            query: q,
            collection: collection,
            year: year,
            generated_at: new Date().toISOString(),
            time_ms: Date.now() - startTime
        };
        
        // Cache for 1 hour
        await redis.setex(cacheKey, 3600, JSON.stringify(result));
        
        res.set('X-Cache', 'MISS');
        res.json(result);
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Single repo endpoint (like /watch in YouTube)
app.get('/repo/:owner/:name', async (req, res) => {
    const startTime = Date.now();
    
    try {
        const { owner, name } = req.params;
        const repo = `${owner}/${name}`;
        
        const cacheKey = `repo:${repo}:detail`;
        
        // Check cache
        const cached = await redis.get(cacheKey);
        if (cached) {
            res.set('X-Cache', 'HIT');
            return res.json(JSON.parse(cached));
        }
        
        // Fetch repo details
        const response = await axios.post('http://localhost:5002/v1/github/fetch', {
            repos: [repo],
            extract_media: true,
            include_readme: true
        }, {
            headers: { 'Authorization': API_KEY }
        });
        
        const repoData = response.data.items[0];
        
        // Get related repos (via topics)
        let related = [];
        if (repoData.topics && repoData.topics.length > 0) {
            const topicQuery = repoData.topics.slice(0, 3).join(' ');
            const searchResponse = await axios.get('http://localhost:5002/v1/github/search', {
                params: { q: topicQuery, per_page: 5 },
                headers: { 'Authorization': API_KEY }
            });
            related = searchResponse.data.items.filter(r => r.repo !== repo);
        }
        
        // Get vintage alternatives from Archive.org
        let vintage = [];
        try {
            const archiveResponse = await axios.post('http://localhost:5001/v1/archive/search', {
                query: name,
                max_items: 3,
                collections: ['softwarelibrary_msdos', 'softwarelibrary_win95']
            }, {
                headers: { 'Authorization': API_KEY }
            });
            vintage = archiveResponse.data.items;
        } catch (err) {
            console.log(`[Archive] Error: ${err.message}`);
        }
        
        const result = {
            repo: repoData,
            related: related,
            vintage: vintage,
            generated_at: new Date().toISOString(),
            time_ms: Date.now() - startTime
        };
        
        // Cache for 1 hour
        await redis.setex(cacheKey, 3600, JSON.stringify(result));
        
        res.set('X-Cache', 'MISS');
        res.json(result);
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ============= CACHE MANAGEMENT =============
app.post('/cache/invalidate', async (req, res) => {
    try {
        const { repo } = req.body;
        if (!repo) {
            return res.status(400).json({ error: 'Missing repo' });
        }
        
        const repos = Array.isArray(repo) ? repo : [repo];
        let deleted = 0;
        
        for (const singleRepo of repos) {
            const cacheKey = crypto.createHash('md5')
                .update(singleRepo)
                .digest('hex');
            
            await redis.del(`discover:${cacheKey}`);
            await redis.del(`repo:${singleRepo}:detail`);
            deleted++;
        }
        
        res.json({ 
            success: true, 
            message: `Invalidated ${deleted} cache entries` 
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/cache/clear-all', async (req, res) => {
    try {
        const allKeys = await redis.keys('discover:*');
        const repoKeys = await redis.keys('repo:*');
        const trendingKeys = await redis.keys('trending:*');
        const searchKeys = await redis.keys('search:*');
        const archiveKeys = await redis.keys('archive:*');
        
        const all = [...allKeys, ...repoKeys, ...trendingKeys, ...searchKeys, ...archiveKeys];
        
        if (all.length > 0) {
            await redis.del(...all);
        }
        
        // Clear queues
        await repoQueue.empty();
        await analysisQueue.empty();
        
        res.json({ 
            success: true, 
            message: `Cleared ${all.length} cache entries and emptied queues` 
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Health check
app.get('/health', async (req, res) => {
    try {
        const [githubHealth, archiveHealth] = await Promise.all([
            axios.get('http://localhost:5002/health', { timeout: 2000 }).catch(() => ({ data: { status: 'error' } })),
            axios.get('http://localhost:5001/health', { timeout: 2000 }).catch(() => ({ data: { status: 'error' } }))
        ]);
        
        const [repoWaiting, repoActive, analysisWaiting, analysisActive] = await Promise.all([
            repoQueue.getWaitingCount(),
            repoQueue.getActiveCount(),
            analysisQueue.getWaitingCount(),
            analysisQueue.getActiveCount()
        ]);
        
        res.json({
            status: 'healthy',
            timestamp: Date.now(),
            services: {
                github: githubHealth.data.status || 'error',
                archive: archiveHealth.data.status || 'error',
                redis: redis.status === 'ready' ? 'healthy' : 'connecting'
            },
            queues: {
                repo: { waiting: repoWaiting, active: repoActive },
                analysis: { waiting: analysisWaiting, active: analysisWaiting }
            },
            endpoints: {
                discover: 'GET /?repo=user/repo&repo=user/repo2',
                trending: 'GET /trending?language=javascript&since=daily',
                search: 'GET /search?q=game+engine',
                archive: 'GET /archive?q=prince+of+persia',
                repo: 'GET /repo/:owner/:name',
                recache: '&recache=1',
                queue: 'GET /queue/stats'
            }
        });
    } catch (error) {
        res.json({ status: 'degraded', error: error.message });
    }
});

// Stats endpoint
app.get('/stats', async (req, res) => {
    try {
        const discoverKeys = await redis.keys('discover:*');
        const repoKeys = await redis.keys('repo:*');
        const trendingKeys = await redis.keys('trending:*');
        const searchKeys = await redis.keys('search:*');
        const archiveKeys = await redis.keys('archive:*');
        
        const [repoWaiting, repoActive, repoCompleted, repoFailed,
               analysisWaiting, analysisActive, analysisCompleted, analysisFailed] = await Promise.all([
            repoQueue.getWaitingCount(), repoQueue.getActiveCount(),
            repoQueue.getCompletedCount(), repoQueue.getFailedCount(),
            analysisQueue.getWaitingCount(), analysisQueue.getActiveCount(),
            analysisQueue.getCompletedCount(), analysisQueue.getFailedCount()
        ]);
        
        res.json({
            cache: {
                discover_entries: discoverKeys.length,
                repo_details: repoKeys.length,
                trending_entries: trendingKeys.length,
                search_entries: searchKeys.length,
                archive_entries: archiveKeys.length,
                total: discoverKeys.length + repoKeys.length + trendingKeys.length + searchKeys.length + archiveKeys.length
            },
            queues: {
                repo: {
                    waiting: repoWaiting,
                    active: repoActive,
                    completed: repoCompleted,
                    failed: repoFailed,
                    concurrency: MAX_CONCURRENT
                },
                analysis: {
                    waiting: analysisWaiting,
                    active: analysisActive,
                    completed: analysisCompleted,
                    failed: analysisFailed,
                    concurrency: 2
                }
            },
            uptime: process.uptime()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ Discovery API Gateway running on port ${PORT}`);
    console.log(`   GitHub service: http://localhost:5002`);
    console.log(`   Archive.org service: http://localhost:5001`);
    console.log(`   Redis: connected`);
    console.log(`   Queues: Repo (${MAX_CONCURRENT} concurrent) | Analysis (2 concurrent)`);
    console.log(`   Internal API Key: ${API_KEY}`);
    console.log('');
    console.log(`   📍 URL PATTERNS`);
    console.log(`   ==================================`);
    console.log(`   📄 Discover repos:`);
    console.log(`   https://${process.env.DOMAIN_NAME || 'discover.sdappnet.cloud'}/?repo=blender/blender&repo=microsoft/vscode`);
    console.log(``);
    console.log(`   🔥 Trending:`);
    console.log(`   https://${process.env.DOMAIN_NAME || 'discover.sdappnet.cloud'}/trending?language=javascript&since=weekly`);
    console.log(``);
    console.log(`   🔍 Search:`);
    console.log(`   https://${process.env.DOMAIN_NAME || 'discover.sdappnet.cloud'}/search?q=game+engine`);
    console.log(``);
    console.log(`   📀 Vintage software:`);
    console.log(`   https://${process.env.DOMAIN_NAME || 'discover.sdappnet.cloud'}/archive?q=prince+of+persia`);
    console.log(``);
    console.log(`   👁️  Watch repo (like YouTube video page):`);
    console.log(`   https://${process.env.DOMAIN_NAME || 'discover.sdappnet.cloud'}/repo/blender/blender`);
    console.log(``);
    console.log(`   🔄 With recache:`);
    console.log(`   https://${process.env.DOMAIN_NAME || 'discover.sdappnet.cloud'}/?repo=blender/blender&recache=1`);
    console.log(``);
    console.log(`   Queue stats: https://${process.env.DOMAIN_NAME || 'discover.sdappnet.cloud'}/queue/stats`);
});
EOF

# Install Node.js dependencies
cd /opt/discovery-platform/api
npm init -y
npm install express axios ioredis bull uuid

# ============= PART 4: SETUP REDIS FOR CACHING =============
log "Configuring Redis for caching..."
cat >> /etc/redis/redis.conf << EOF
# Optimize for caching
maxmemory 128mb
maxmemory-policy allkeys-lru
save ""  # Disable persistence
EOF

systemctl restart redis-server

# ============= PART 5: SETUP PM2 ECOSYSTEM =============
log "Creating PM2 ecosystem..."

cat > /opt/discovery-platform/ecosystem.config.js << EOF
module.exports = {
    apps: [
        {
            name: 'archive-service',
            cwd: '/opt/discovery-platform/api',
            script: '/opt/discovery-platform/venv/bin/uvicorn',
            args: 'archive_service:app --host 0.0.0.0 --port 5001',
            interpreter: '/opt/discovery-platform/venv/bin/python',
            watch: false,
            instances: 1,
            exec_mode: 'fork',
            max_memory_restart: '150M',
            env: {
                API_KEY: '${API_KEY}'
            }
        },
        {
            name: 'github-service',
            cwd: '/opt/discovery-platform/api',
            script: '/opt/discovery-platform/venv/bin/uvicorn',
            args: 'github_service:app --host 0.0.0.0 --port 5002',
            interpreter: '/opt/discovery-platform/venv/bin/python',
            watch: false,
            instances: 1,
            exec_mode: 'fork',
            max_memory_restart: '150M',
            env: {
                API_KEY: '${API_KEY}',
                GITHUB_TOKEN: '${GITHUB_TOKEN}'
            }
        },
        {
            name: 'api-gateway',
            cwd: '/opt/discovery-platform/api',
            script: 'gateway.js',
            watch: false,
            instances: 1,
            exec_mode: 'fork',
            max_memory_restart: '150M',
            env: {
                PORT: 3000,
                API_KEY: '${API_KEY}',
                GITHUB_TOKEN: '${GITHUB_TOKEN}',
                DOMAIN_NAME: '${DOMAIN_NAME}',
                MAX_CONCURRENT: ${MAX_CONCURRENT}
            }
        }
    ]
};
EOF

# Start services with PM2
log "Starting services..."
pm2 start /opt/discovery-platform/ecosystem.config.js
pm2 save
pm2 startup

# ============= PART 6: SETUP SSL WITH NGINX =============
log "Setting up nginx and SSL..."

# Install nginx and certbot
apt-get install -y -qq nginx certbot python3-certbot-nginx

# Stop any services on port 80
systemctl stop nginx 2>/dev/null || true
pkill -f nginx 2>/dev/null || true
fuser -k 80/tcp 2>/dev/null || true
sleep 2

# Get SSL certificate
log "Obtaining SSL certificate for $DOMAIN_NAME..."
if certbot certonly --standalone -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "$SSL_EMAIL"; then
    log "✅ SSL certificate obtained successfully"
    SSL_ENABLED=true
else
    warn "SSL certificate failed. Continuing with HTTP only..."
    SSL_ENABLED=false
fi

# Create nginx configuration
log "Creating nginx configuration..."

if [ "$SSL_ENABLED" = true ]; then
    cat > /etc/nginx/sites-available/$DOMAIN_NAME << EOF
# HTTP redirect
server {
    listen 80;
    server_name $DOMAIN_NAME $DROPLET_IP;
    return 301 https://\$server_name\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Add cache headers
    add_header X-Cache-Status \$upstream_cache_status;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 120s;
    }
    
    location = /health {
        proxy_pass http://127.0.0.1:3000/health;
        access_log off;
    }
    
    location = /stats {
        proxy_pass http://127.0.0.1:3000/stats;
        access_log off;
    }
    
    location = /queue/stats {
        proxy_pass http://127.0.0.1:3000/queue/stats;
        access_log off;
    }
}
EOF
else
    cat > /etc/nginx/sites-available/$DOMAIN_NAME << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME $DROPLET_IP;
    
    add_header X-Cache-Status \$upstream_cache_status;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 120s;
    }
    
    location = /health {
        proxy_pass http://127.0.0.1:3000/health;
        access_log off;
    }
    
    location = /stats {
        proxy_pass http://127.0.0.1:3000/stats;
        access_log off;
    }
    
    location = /queue/stats {
        proxy_pass http://127.0.0.1:3000/queue/stats;
        access_log off;
    }
}
EOF
fi

# Enable site
ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx
nginx -t && systemctl start nginx

# Add to hosts file
if ! grep -q "$DOMAIN_NAME" /etc/hosts; then
    sed -i "/127.0.0.1 localhost/a 127.0.0.1 $DOMAIN_NAME" /etc/hosts
fi

# ============= PART 7: CREATE TEST SCRIPT =============
log "Creating test script..."

cat > /opt/discovery-platform/test-discovery.sh << 'EOF'
#!/bin/bash

DOMAIN_NAME="$DOMAIN_NAME"
SSL_ENABLED=$SSL_ENABLED

echo "=== Discovery Platform Test v1.0 ==="
echo "Domain: $DOMAIN_NAME"
echo ""

# Test repos
TEST_REPO1="blender/blender"
TEST_REPO2="microsoft/vscode"
TEST_REPO3="godotengine/godot"

# Test 1: Discover repos
echo "1. Testing DISCOVERY (multiple repos)..."
if [ "$SSL_ENABLED" = true ]; then
    curl -s "https://$DOMAIN_NAME/?repo=$TEST_REPO1&repo=$TEST_REPO2" | grep -o '"total":[0-9]*' | head -1
else
    curl -s "http://$DOMAIN_NAME/?repo=$TEST_REPO1&repo=$TEST_REPO2" | grep -o '"total":[0-9]*' | head -1
fi
echo "   ✅ Discovery complete"
echo ""

# Test 2: Trending
echo "2. Testing TRENDING..."
if [ "$SSL_ENABLED" = true ]; then
    curl -s "https://$DOMAIN_NAME/trending?language=javascript&since=daily" | grep -o '"total":[0-9]*' | head -1
else
    curl -s "http://$DOMAIN_NAME/trending?language=javascript&since=daily" | grep -o '"total":[0-9]*' | head -1
fi
echo "   ✅ Trending complete"
echo ""

# Test 3: Search
echo "3. Testing SEARCH..."
if [ "$SSL_ENABLED" = true ]; then
    curl -s "https://$DOMAIN_NAME/search?q=game+engine" | grep -o '"total_count":[0-9]*' | head -1
else
    curl -s "http://$DOMAIN_NAME/search?q=game+engine" | grep -o '"total_count":[0-9]*' | head -1
fi
echo "   ✅ Search complete"
echo ""

# Test 4: Archive search
echo "4. Testing ARCHIVE search..."
if [ "$SSL_ENABLED" = true ]; then
    curl -s "https://$DOMAIN_NAME/archive?q=prince+of+persia&limit=2" | grep -o '"total":[0-9]*' | head -1
else
    curl -s "http://$DOMAIN_NAME/archive?q=prince+of+persia&limit=2" | grep -o '"total":[0-9]*' | head -1
fi
echo "   ✅ Archive search complete"
echo ""

# Test 5: Single repo (watch page)
echo "5. Testing REPO WATCH page..."
if [ "$SSL_ENABLED" = true ]; then
    curl -s "https://$DOMAIN_NAME/repo/blender/blender" | grep -o '"repo":"[^"]*"' | head -1
else
    curl -s "http://$DOMAIN_NAME/repo/blender/blender" | grep -o '"repo":"[^"]*"' | head -1
fi
echo "   ✅ Repo watch complete"
echo ""

# Test 6: Queue stats
echo "6. Checking queue stats..."
if [ "$SSL_ENABLED" = true ]; then
    curl -s "https://$DOMAIN_NAME/queue/stats" | grep -o '"repo":{[^}]*}' | head -1
else
    curl -s "http://$DOMAIN_NAME/queue/stats" | grep -o '"repo":{[^}]*}' | head -1
fi
echo "   ✅ Queue stats retrieved"
echo ""

echo "=== Test Complete ==="
echo ""
echo "Your Discovery Platform is ready!"
EOF

chmod +x /opt/discovery-platform/test-discovery.sh

# ============= PART 8: CREATE MONITORING SCRIPT =============
log "Creating monitoring script..."

cat > /usr/local/bin/monitor-discovery.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/discovery-monitor.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check API Gateway
if ! pm2 list | grep -q api-gateway; then
    log_message "API Gateway not running - restarting"
    pm2 restart api-gateway
fi

# Check GitHub Service
if ! pm2 list | grep -q github-service; then
    log_message "GitHub Service not running - restarting"
    pm2 restart github-service
fi

# Check Archive Service
if ! pm2 list | grep -q archive-service; then
    log_message "Archive Service not running - restarting"
    pm2 restart archive-service
fi

# Check Redis
if ! systemctl is-active --quiet redis-server; then
    log_message "Redis not running - restarting"
    systemctl restart redis-server
fi

# Check queue sizes
QUEUE_STATS=$(curl -s http://localhost:3000/queue/stats 2>/dev/null)
if [ -n "$QUEUE_STATS" ]; then
    REPO_WAITING=$(echo "$QUEUE_STATS" | grep -o '"repo":{[^}]*"waiting":[0-9]*' | grep -o '"waiting":[0-9]*' | cut -d':' -f2)
    ANALYSIS_WAITING=$(echo "$QUEUE_STATS" | grep -o '"analysis":{[^}]*"waiting":[0-9]*' | grep -o '"waiting":[0-9]*' | cut -d':' -f2)
    
    log_message "Queue stats - Repo: $REPO_WAITING waiting, Analysis: $ANALYSIS_WAITING waiting"
    
    if [ "$REPO_WAITING" -gt 50 ] || [ "$ANALYSIS_WAITING" -gt 20 ]; then
        log_message "⚠️ Queue backup!"
    fi
fi

# Check cache size
CACHE_KEYS=$(redis-cli keys "discover:*" 2>/dev/null | wc -l)
log_message "Cache entries: $CACHE_KEYS"

# Check memory
MEM_FREE=$(free -m | awk 'NR==2 {print $7}')
if [ "$MEM_FREE" -lt 50 ]; then
    log_message "⚠️ Low memory (${MEM_FREE}MB free) - clearing cache"
    redis-cli FLUSHDB
fi

log_message "Monitoring check completed"
EOF

chmod +x /usr/local/bin/monitor-discovery.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/monitor-discovery.sh") | crontab -

# ============= PART 9: CREATE SYSTEMD SERVICE =============
log "Creating systemd service..."

cat > /etc/systemd/system/discovery-platform.service << EOF
[Unit]
Description=Discovery Platform with GitHub + Archive.org
After=network.target redis-server.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/pm2 start /opt/discovery-platform/ecosystem.config.js
ExecStop=/usr/bin/pm2 stop all
ExecReload=/usr/bin/pm2 reload all
User=root
Group=root
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable discovery-platform.service
systemctl start discovery-platform.service

# ============= FINAL SETUP =============

# Run initial test
log "Running initial test..."
if /opt/discovery-platform/test-discovery.sh; then
    log "✅ Initial test passed!"
else
    warn "Initial test had issues. Check logs above."
fi

# Final output
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   DISCOVERY PLATFORM SETUP COMPLETE! v1.0               ║${NC}"
echo -e "${GREEN}║   GitHub + Archive.org + Media extraction               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Your Discovery Platform is ready!"
echo ""
info "Public URL:"
if [ "$SSL_ENABLED" = true ]; then
    echo "  🔒 HTTPS: https://$DOMAIN_NAME"
else
    echo "  🌐 HTTP: http://$DOMAIN_NAME"
fi
echo ""
info "📍 URL PATTERNS (YouTube for software!)"
echo "=========================================="
echo ""
info "📄 Discover multiple repos (like YouTube playlist):"
echo "  curl \"https://$DOMAIN_NAME/?repo=blender/blender&repo=microsoft/vscode\""
echo ""
info "🔥 Trending repos (like YouTube trending):"
echo "  curl \"https://$DOMAIN_NAME/trending?language=javascript&since=weekly\""
echo ""
info "🔍 Search (like YouTube search):"
echo "  curl \"https://$DOMAIN_NAME/search?q=game+engine\""
echo ""
info "📀 Vintage software from Archive.org:"
echo "  curl \"https://$DOMAIN_NAME/archive?q=prince+of+persia\""
echo ""
info "👁️  Watch a repo (like YouTube video page):"
echo "  curl \"https://$DOMAIN_NAME/repo/blender/blender\""
echo ""
info "🔄 With recache (force refresh):"
echo "  curl \"https://$DOMAIN_NAME/?repo=blender/blender&recache=1\""
echo ""
info "Queue Management:"
echo "  📊 Queue stats: curl https://$DOMAIN_NAME/queue/stats"
echo "  ⚡ Repo concurrent: $MAX_CONCURRENT jobs | Analysis concurrent: 2 jobs"
echo ""
info "Quick test:"
echo "  cd /opt/discovery-platform && ./test-discovery.sh"
echo ""
info "Cache management:"
echo "  📊 Stats: curl https://$DOMAIN_NAME/stats"
echo "  🧹 Invalidate: curl -X POST https://$DOMAIN_NAME/cache/invalidate \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"repo\":\"blender/blender\"}'"
echo "  🗑️ Clear all: curl -X POST https://$DOMAIN_NAME/cache/clear-all"
echo ""
info "Management commands:"
echo "  📊 Status: pm2 list"
echo "  📝 Logs: pm2 logs"
echo "  🔄 Restart: systemctl restart discovery-platform"
echo ""
log "✨ Setup complete! Your Discovery Platform handles:"
log "   • GitHub repos with README media extraction (images, YouTube links)"
log "   • Archive.org vintage software with screenshots"
log "   • Queue system for multiple repos"
log "   • Trending, search, and watch pages"
log "   • Like YouTube but for software discovery! 🚀"

# What You've Built:
# ├── 📄 Discover repos: /?repo=user/repo&repo=user/repo2
# ├── 🔥 Trending: /trending?language=javascript
# ├── 🔍 Search: /search?q=game+engine
# ├── 📀 Vintage: /archive?q=prince+of+persia
# ├── 👁️  Watch: /repo/user/repo (like YouTube video page)
# ├── 🔄 Recache: &recache=1
# ├── 🚦 Queue system (5 concurrent)
# ├── 💾 Redis cache (1 hour TTL)
# └── 🎨 Ready for your YouTube UI!

# The $4/Month Magic:
# // Traditional discovery platform:
# GitHub API calls: $$$ 
# Database: $50/mo
# Media extraction: complex
# Total: $100+/mo

# // Your solution: $4/mo
# // Same features, 98% cheaper, self-hosted, no limits