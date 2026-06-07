#!/usr/bin/env python3
"""
Baseline Index Cache (Experiment 3)

Caches carrier search results in BASELINE_INDEX.md to reduce Phase 0 duration.
This avoids re-running the same rg queries every round for known structures.
"""

import sys
import re
import subprocess
import json
import hashlib
import time
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime


DEFAULT_CACHE_DIR = Path(".baseline_index")
CACHE_FILE = DEFAULT_CACHE_DIR / "carrier_search_cache.json"
CACHE_SECTION = "carrier_search_cache"


def get_baseline_commit(worktree: Path) -> str:
    """Get the baseline commit hash for the worktree."""
    try:
        result = subprocess.run(
            ['git', 'rev-parse', 'HEAD'],
            cwd=worktree,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return "unknown"


def generate_cache_key(query: str, worktree: str) -> str:
    """Generate cache key from query and worktree path."""
    key_content = f"{query}:{worktree}"
    return hashlib.sha256(key_content.encode()).hexdigest()[:16]


def run_rg_query(query: str, worktree: Path, file_type: str = "java") -> Dict:
    """Run ripgrep query and return results."""
    try:
        result = subprocess.run(
            ['rg', query, '-t', file_type, '--json', '--no-line-number'],
            cwd=worktree,
            capture_output=True,
            text=True,
            timeout=60
        )

        matches = []
        if result.stdout:
            for line in result.stdout.strip().split('\n'):
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    if data.get('type') == 'match':
                        matches.append({
                            'path': data.get('path', {}),
                            'lines': data.get('lines', {})
                        })
                except json.JSONDecodeError:
                    continue

        return {
            "query": query,
            "matches_count": len(matches),
            "matches": matches[:100]  # Limit to 100 matches
        }

    except (subprocess.TimeoutExpired, FileNotFoundError, Exception) as e:
        return {
            "query": query,
            "error": str(e),
            "matches_count": 0,
            "matches": []
        }


def load_cache() -> Dict:
    """Load carrier search cache from disk."""
    if not CACHE_FILE.exists():
        return {}

    try:
        with open(CACHE_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}


def save_cache(cache: Dict) -> None:
    """Save carrier search cache to disk."""
    try:
        DEFAULT_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        with open(CACHE_FILE, 'w', encoding='utf-8') as f:
            json.dump(cache, f, indent=2, ensure_ascii=False)
    except Exception:
        pass


def get_cached_or_search(
    query: str,
    worktree: Path,
    file_type: str = "java",
    force_refresh: bool = False
) -> Dict:
    """
    Get cached search results or run new search.

    Returns dict with:
    - cached: bool
    - results: search results
    - cache_hit: bool
    - timestamp: when result was generated
    """
    worktree_str = str(worktree)
    baseline_commit = get_baseline_commit(worktree)
    cache_key = generate_cache_key(query, worktree_str)

    # Load cache
    cache = load_cache()

    # Check if cached result exists and is valid
    if not force_refresh and CACHE_SECTION in cache:
        cached_entry = cache[CACHE_SECTION].get(cache_key)
        if cached_entry:
            # Verify baseline commit matches
            if cached_entry.get("baseline_commit") == baseline_commit:
                return {
                    "cached": True,
                    "cache_hit": True,
                    "results": cached_entry.get("results", {}),
                    "cached_at": cached_entry.get("cached_at"),
                    "query": query
                }

    # Cache miss or invalid - run search
    search_results = run_rg_query(query, worktree, file_type)

    # Update cache
    if CACHE_SECTION not in cache:
        cache[CACHE_SECTION] = {}

    cache[CACHE_SECTION][cache_key] = {
        "query": query,
        "worktree": worktree_str,
        "baseline_commit": baseline_commit,
        "results": search_results,
        "cached_at": datetime.now().isoformat(),
        "file_type": file_type
    }

    save_cache(cache)

    return {
        "cached": False,
        "cache_hit": False,
        "results": search_results,
        "cached_at": datetime.now().isoformat(),
        "query": query
    }


def invalidate_cache(worktree: Optional[Path] = None) -> Dict:
    """Invalidate cache (optionally only for specific worktree)."""
    cache = load_cache()

    if worktree is None:
        # Clear entire cache
        cache[CACHE_SECTION] = {}
        save_cache(cache)
        return {"cleared": True, "entries_cleared": "all"}
    else:
        # Clear only entries for specific worktree
        worktree_str = str(worktree)
        cleared_count = 0

        if CACHE_SECTION in cache:
            keys_to_remove = []
            for key, entry in cache[CACHE_SECTION].items():
                if entry.get("worktree") == worktree_str:
                    keys_to_remove.append(key)

            for key in keys_to_remove:
                del cache[CACHE_SECTION][key]
                cleared_count += 1

        save_cache(cache)
        return {"cleared": True, "entries_cleared": cleared_count}


def get_cache_stats() -> Dict:
    """Get cache statistics."""
    cache = load_cache()

    if CACHE_SECTION not in cache:
        return {"total_entries": 0, "size_bytes": 0}

    entries = cache[CACHE_SECTION]
    total_entries = len(entries)

    # Calculate size
    size_bytes = CACHE_FILE.stat().st_size if CACHE_FILE.exists() else 0

    # Count by worktree
    by_worktree = {}
    for entry in entries.values():
        worktree = entry.get("worktree", "unknown")
        by_worktree[worktree] = by_worktree.get(worktree, 0) + 1

    return {
        "total_entries": total_entries,
        "size_bytes": size_bytes,
        "by_worktree": by_worktree,
        "cache_file": str(CACHE_FILE)
    }


def search_with_cache(
    queries: List[str],
    worktree: Path,
    file_type: str = "java"
) -> Dict:
    """
    Run multiple searches with caching.

    Returns dict with:
    - queries: list of query results
    - cache_hits: number of cache hits
    - cache_misses: number of cache misses
    - total_time: approximate time (not precise)
    """
    results = []
    cache_hits = 0
    cache_misses = 0
    start_time = time.time()

    for query in queries:
        result = get_cached_or_search(query, worktree, file_type)
        results.append(result)

        if result.get("cache_hit"):
            cache_hits += 1
        else:
            cache_misses += 1

    total_time = time.time() - start_time

    return {
        "queries": results,
        "cache_hits": cache_hits,
        "cache_misses": cache_misses,
        "cache_hit_rate": f"{(cache_hits / len(queries) * 100):.1f}%" if queries else "0%",
        "total_time_seconds": round(total_time, 2),
        "average_time_per_query": round(total_time / len(queries), 2) if queries else 0
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: baseline_index_cache.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  search <query> <worktree> [file_type]", file=sys.stderr)
        print("  batch-search <queries_json> <worktree> [file_type]", file=sys.stderr)
        print("  stats", file=sys.stderr)
        print("  invalidate [worktree]", file=sys.stderr)
        print("  baseline-commit <worktree>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "search":
        if len(sys.argv) < 4:
            print("Usage: baseline_index_cache.py search <query> <worktree> [file_type]", file=sys.stderr)
            sys.exit(1)

        query = sys.argv[2]
        worktree = Path(sys.argv[3])
        file_type = sys.argv[4] if len(sys.argv) > 4 else "java"

        result = get_cached_or_search(query, worktree, file_type)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "batch-search":
        if len(sys.argv) < 4:
            print("Usage: baseline_index_cache.py batch-search <queries_json> <worktree> [file_type]", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            queries = json.load(f)
        worktree = Path(sys.argv[3])
        file_type = sys.argv[4] if len(sys.argv) > 4 else "java"

        result = search_with_cache(queries, worktree, file_type)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "stats":
        stats = get_cache_stats()
        print(json.dumps(stats, indent=2, ensure_ascii=False))

    elif command == "invalidate":
        worktree = Path(sys.argv[2]) if len(sys.argv) > 2 else None
        result = invalidate_cache(worktree)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "baseline-commit":
        if len(sys.argv) < 3:
            print("Usage: baseline_index_cache.py baseline-commit <worktree>", file=sys.stderr)
            sys.exit(1)

        worktree = Path(sys.argv[2])
        commit = get_baseline_commit(worktree)
        print(json.dumps({"baseline_commit": commit}, ensure_ascii=False))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
