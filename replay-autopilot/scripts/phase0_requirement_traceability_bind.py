#!/usr/bin/env python3
"""
Requirement Traceability Binding (Experiment 1 from NEXT_EXPERIMENT_PLAN.md).

Maps requirement action phrases to exact production carriers using source grep.
Creates REQUIREMENT_CARRIER_BINDINGS.json before planning starts.

This prevents the anti-pattern where agents select wrong processors
(e.g., AiCalculateLossApiTaskProcessor instead of AiApplyClaimApiTaskProcessor).
"""

import json
import re
import sys
import subprocess
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional


# Action phrase extraction patterns
ACTION_PHRASE_PATTERNS = [
    r'([A-Za-z]+(?:申请|核赔|理算|报案|审核|支付|通知|回调|查询|取消)[A-Za-z]*)',
    r'(AI\s*[A-Za-z]+(?:申请|核赔|理算))',
    r'([A-Za-z]*(?:Apply|Claim|Calculate|Review|Report|Audit|Payment|Notify|Callback|Query|Cancel)[A-Za-z]*)',
]

# Workflow keyword mappings (Chinese to English)
WORKFLOW_KEYWORD_MAP = {
    '申请': ['Apply', 'Application', 'Submit', 'Create'],
    '核赔': ['Claim', 'Review', 'Calculate'],
    '理算': ['Calculate', 'Settlement', 'Loss'],
    '报案': ['Report', 'Register', 'Case'],
    '审核': ['Review', 'Audit', 'Approve', 'Verify'],
    '支付': ['Payment', 'Pay', 'Transfer'],
    '通知': ['Notify', 'Notification'],
    '回调': ['Callback', 'Handle', 'Response'],
    '查询': ['Query', 'Search', 'Get', 'Find'],
    '取消': ['Cancel', 'Close', 'Terminate'],
}


def extract_action_phrases(requirement_text: str) -> Set[str]:
    """
    Extract action phrases from requirement text.

    Looks for patterns like:
    - "AI核赔申请"
    - "自动理算"
    - "免复核金额配置"
    """
    phrases = set()

    # Extract Chinese keywords first
    for chinese, english_list in WORKFLOW_KEYWORD_MAP.items():
        if chinese in requirement_text:
            phrases.update(english_list)

    # Extract direct action phrases
    for pattern in ACTION_PHRASE_PATTERNS:
        matches = re.finditer(pattern, requirement_text, re.IGNORECASE)
        for match in matches:
            phrase = match.group(1).strip()
            if len(phrase) >= 3:  # Minimum meaningful length
                phrases.add(phrase)

    return phrases


def grep_worktree(worktree: Path, phrase: str, pattern: str = "*TaskProcessor.java") -> List[Dict]:
    """
    Search worktree for phrase matching files.

    Returns list of {file, line, context} matches.
    """
    results = []

    try:
        # Use ripgrep if available, otherwise fall back to grep
        cmd = ['rg', '-i', '--json', phrase, '-g', pattern, str(worktree)]
        try:
            output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
            lines = output.strip().split('\n')
            for line in lines:
                if line:
                    try:
                        data = json.loads(line)
                        if data.get('type') == 'match':
                            results.append({
                                'file': data.get('data', {}).get('path', {}).get('text', ''),
                                'line': data.get('data', {}).get('line_number', 0),
                                'context': data.get('data', {}).get('lines', {}).get('text', '')
                            })
                    except json.JSONDecodeError:
                        continue
        except (subprocess.CalledProcessError, FileNotFoundError):
            # Fall back to Python glob search
            for java_file in worktree.rglob(pattern):
                try:
                    content = java_file.read_text(encoding='utf-8', errors='ignore')
                    if re.search(re.escape(phrase), content, re.IGNORECASE):
                        lines = content.split('\n')
                        for i, line in enumerate(lines):
                            if re.search(re.escape(phrase), line, re.IGNORECASE):
                                results.append({
                                    'file': str(java_file.relative_to(worktree)),
                                    'line': i + 1,
                                    'context': line.strip()
                                })
                                break
                except:
                    continue
    except Exception as e:
        pass

    return results


def select_best_match(matches: List[Dict], phrase: str) -> Optional[Dict]:
    """
    Select the best match from multiple results.

    Prioritizes:
    1. Class name containing the phrase
    2. Method name containing the phrase
    3. Most specific match (longer context)
    """
    if not matches:
        return None

    # Sort by specificity (context length, then line number)
    scored = []
    for match in matches:
        score = 0

        # Check if class name contains phrase
        file_path = match.get('file', '')
        class_name = Path(file_path).stem
        if phrase.lower() in class_name.lower():
            score += 100

        # Check if context has method signature
        context = match.get('context', '')
        if 'public' in context or 'void' in context:
            score += 10

        # Prefer matches with more context
        score += len(context)

        scored.append((score, match))

    scored.sort(key=lambda x: x[0], reverse=True)
    return scored[0][1] if scored else None


def requirement_traceability_bind(
    worktree_path: str,
    requirement_source_path: str,
    output_path: str
) -> Dict:
    """
    Maps requirement action phrases to exact production carriers.

    Returns dict with bindings and validation result.
    """
    worktree = Path(worktree_path)
    requirement_path = Path(requirement_source_path)
    output_file = Path(output_path)

    if not worktree.exists():
        return {
            'status': 'FAIL',
            'error': 'worktree_not_found',
            'message': f'Worktree not found: {worktree_path}'
        }

    if not requirement_path.exists():
        return {
            'status': 'FAIL',
            'error': 'requirement_not_found',
            'message': f'Requirement source not found: {requirement_source_path}'
        }

    # Read requirement
    requirement_text = requirement_path.read_text(encoding='utf-8', errors='ignore')

    # Extract action phrases
    phrases = extract_action_phrases(requirement_text)

    if not phrases:
        return {
            'status': 'FAIL',
            'error': 'no_action_phrases_found',
            'message': 'No action phrases found in requirement. Cannot bind carriers.'
        }

    # Build bindings
    bindings = {}
    unbound_phrases = []

    for phrase in sorted(phrases):
        # Search for matching carriers
        matches = grep_worktree(worktree, phrase)

        if not matches:
            unbound_phrases.append(phrase)
            continue

        if len(matches) == 1:
            best = matches[0]
        else:
            best = select_best_match(matches, phrase)

        if best:
            # Extract class name from file
            file_path = best.get('file', '')
            class_name = Path(file_path).stem

            bindings[phrase] = {
                'file': file_path,
                'class': class_name,
                'line': best.get('line', 0),
                'context': best.get('context', ''),
                'match_count': len(matches)
            }

    # Check if all phrases bound
    is_complete = len(unbound_phrases) == 0

    result = {
        'status': 'PASS' if is_complete else 'PARTIAL',
        'bindings': bindings,
        'unbound_phrases': sorted(unbound_phrases),
        'total_phrases': len(phrases),
        'bound_count': len(bindings),
        'unbound_count': len(unbound_phrases),
        'message': (
            f'All {len(phrases)} action phrases bound to carriers'
            if is_complete else
            f'{len(bindings)}/{len(phrases)} phrases bound, {len(unbound_phrases)} unbound: {unbound_phrases}'
        )
    }

    # Write bindings to output
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    return result


def main():
    if len(sys.argv) < 4:
        print("Usage: phase0_requirement_traceability_bind.py <worktree> <requirement.md> <output.json>", file=sys.stderr)
        sys.exit(1)

    worktree_path = sys.argv[1]
    requirement_path = sys.argv[2]
    output_path = sys.argv[3]

    result = requirement_traceability_bind(worktree_path, requirement_path, output_path)

    print(json.dumps(result, indent=2, ensure_ascii=False))
    sys.exit(0 if result['status'] in ('PASS', 'PARTIAL') else 1)


if __name__ == '__main__':
    main()
