import re

def is_ascii(s: str) -> bool:
    """文字列がすべてASCII文字で構成されているかを判定する"""
    return all(ord(c) < 128 for c in s)

def remove_forbidden_blocks(xml_content: str) -> str:
    """
    プロンプトで禁止されている、音楽再生に必須でないタグブロックを正規表現で完全に削除する。
    これにより、AIが生成した不要なフォーマット情報や危険な要素を根こそぎ駆除する。
    """
    # 削除対象のタグ名をリストで定義
    # これらはブロックごと（<tag>...</tag>）削除される
    tags_to_remove = [
        "print", 
        "identification",
        "work",
        "harmony", 
        "lyric",
        "ornaments",
        "technical",
        "measure-style", 
        "staff-layout",
        "appearance",
        "measure-layout",
        "beam"
    ]
    
    for tag in tags_to_remove:
        # <tag...> から </tag> までのブロック全体を、改行も含めて削除する正規表現
        pattern = re.compile(rf'\s*<{tag}.*?</{tag}>\s*', re.DOTALL)
        xml_content = pattern.sub('', xml_content)
        
    return xml_content

def reconstruct_staff_details(xml_content: str) -> str:
    """AIが生成しがちな、構造的に破綻した<staff-details>ブロック全体を再構築する。"""
    pattern = re.compile(r'(<staff-details.*?>\s*(.*?)\s*</staff-details>)', re.DOTALL)
    for match in reversed(list(pattern.finditer(xml_content))):
        full_block_str, inner_content = match.groups()
        start_pos, end_pos = match.span()
        staff_lines_match = re.search(r'<staff-lines>(\d+)</staff-lines>', inner_content)
        staff_lines_tag = staff_lines_match.group(0) if staff_lines_match else '          <staff-lines>5</staff-lines>'
        tuning_pairs_pattern = re.compile(r'<tuning-step>(.*?)</tuning-step>\s*<octave>(.*?)</octave>', re.DOTALL)
        tuning_pairs = tuning_pairs_pattern.findall(inner_content)
        if not tuning_pairs:
            xml_content = xml_content[:start_pos] + '' + xml_content[end_pos:]
            continue
        reconstructed_lines = [f'        <staff-details number="1">', f'          {staff_lines_tag.strip()}']
        for i, (step, octave) in enumerate(tuning_pairs, start=1):
            reconstructed_lines.extend([
                f'          <staff-tuning line="{i}">',
                f'            <tuning-step>{step}</tuning-step>',
                f'            <octave>{octave}</octave>',
                '          </staff-tuning>'
            ])
        reconstructed_lines.append('        </staff-details>')
        reconstructed_block_str = '\n'.join(reconstructed_lines)
        xml_content = xml_content[:start_pos] + reconstructed_block_str + xml_content[end_pos:]
    return xml_content

def correct_stem_structure(xml_content: str) -> str:
    """AIが生成しがちな、不正な構造を持つ<stem>タグを正しい形式に修正する。"""
    pattern = re.compile(r'<stem\s+direction="([^"]+)">\s*<note-stem.*?>\s*</stem>', re.DOTALL)
    def replacer(match):
        return f'<stem>{match.group(1)}</stem>'
    return pattern.sub(replacer, xml_content)

def merge_and_reconstruct_attributes(xml_content: str) -> str:
    """不正に分離された<print>と<attributes>を検出し、単一の正しい<attributes>に統合する。"""
    measure_pattern = re.compile(r'(<measure.*?>)(.*?)(</measure>)', re.DOTALL)
    for measure_match in reversed(list(measure_pattern.finditer(xml_content))):
        measure_start_tag, inner_measure, measure_end_tag = measure_match.groups()
        start_pos, end_pos = measure_match.span()
        pattern_to_fix = re.compile(r'(<print>.*?</print>)\s*(<attributes>.*?</attributes>)', re.DOTALL)
        fix_match = pattern_to_fix.search(inner_measure)
        if fix_match:
            print_block, attributes_block = fix_match.groups()
            combined_block = print_block + attributes_block
            elements = {
                'divisions': re.search(r'<divisions>.*?</divisions>', combined_block, re.DOTALL),
                'key': re.search(r'<key>.*?</key>', combined_block, re.DOTALL),
                'time': re.search(r'<time>.*?</time>', combined_block, re.DOTALL),
                'clef': re.search(r'<clef>.*?</clef>', combined_block, re.DOTALL),
                'staves': re.search(r'<staves>.*?</staves>', combined_block, re.DOTALL),
                'staff-details': re.search(r'<staff-details>.*?</staff-details>', combined_block, re.DOTALL)
            }
            new_attributes_lines = ["      <attributes>"]
            for key, el_match in elements.items():
                if el_match:
                    if key == 'staff-details':
                        new_attributes_lines.append(el_match.group(0))
                    else:
                        new_attributes_lines.append(f"        {el_match.group(0).strip()}")
            new_attributes_lines.append("      </attributes>")
            reconstructed_attributes = "\n".join(new_attributes_lines)
            new_inner_measure = pattern_to_fix.sub(reconstructed_attributes, inner_measure, count=1)
            xml_content = xml_content[:measure_match.start()] + measure_start_tag + new_inner_measure + measure_end_tag + xml_content[end_pos:]
    return xml_content

def correct_common_musicxml_errors(xml_content: str) -> str:
    """
    MusicXML文字列内の、AIが生成しがちな複数の共通エラーを安全に修正します。
    """
    
    # ステップ0: 非ASCII文字を含む不正なタグ行の削除
    lines = xml_content.splitlines()
    cleaned_lines = []
    tag_pattern = re.compile(r'<[^>]+>')
    for line in lines:
        is_safe = True
        tags_in_line = tag_pattern.findall(line)
        for tag in tags_in_line:
            if not is_ascii(tag):
                is_safe = False
                break
        if is_safe:
            cleaned_lines.append(line)
    corrected_content = "\n".join(cleaned_lines)

    # ステップ1: 不要・有害なブロックの完全駆除
    corrected_content = remove_forbidden_blocks(corrected_content)

    # ステップ2: 構造的エラーの修正
    corrected_content = merge_and_reconstruct_attributes(corrected_content)
    corrected_content = reconstruct_staff_details(corrected_content)
    corrected_content = correct_stem_structure(corrected_content)

    # ステップ3: 既知の単純な文字列置換（局所的エラーの修正）
    correction_rules = [
        ("</tuning-tuning>", "</staff-tuning>"),
        ("</tuning>", "</staff-tuning>"),
        ("<notehead>mixed</notehead>", "<notehead>normal</notehead>"),
        ("<notehead>cluster-dot</notehead>", "<notehead>normal</notehead>"),
        ('direction="over"', 'direction="up"'),
    ]
    
    for incorrect, correct in correction_rules:
        corrected_content = corrected_content.replace(incorrect, correct)
        
    # ステップ4: その他の細かいクリーンアップ
    forbidden_substrings_fine = [
        "<sound instrument=",
        "<part-symbol>", "</part-symbol>",
        "<notehead>block-circle</notehead>",
        "<grace-y>", "</grace-y>", "<normal/>",
        "<long-segment/>",
        "<slur", "<tied", # スラーとタイも削除
        "<wedge" # クレッシェンド記号も削除
    ]
    
    lines = corrected_content.splitlines()
    final_cleaned_lines = []
    for line in lines:
        if not any(sub in line for sub in forbidden_substrings_fine):
            final_cleaned_lines.append(line)
            
    corrected_content = "\n".join(final_cleaned_lines)
    
    return corrected_content
