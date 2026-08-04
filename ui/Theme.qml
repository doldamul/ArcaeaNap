pragma Singleton
import QtQuick

QtObject {
    id: theme

    readonly property bool isDarkMode: typeof themeHandler === "undefined" ? false : themeHandler.isDarkMode

    // Base UI
    property color bgWindow: isDarkMode ? "#1A1A1E" : "#F3F4F8"
    property color bgCard: isDarkMode ? "#2A2A2E" : "#FFFFFF"
    property color bgNav: isDarkMode ? "#222226" : "#FFFFFF"
    property color bgInput: isDarkMode ? "#333338" : "#F5F5F5"
    property color bgButton: isDarkMode ? "#3A3A40" : "#F0F0F0"
    property color bgCapsule: isDarkMode ? "#2E2E32" : "#F8F8F8"
    property color bgHover: isDarkMode ? "#454548" : "#E0E0E0"
    property color bgItemHover: isDarkMode ? "#333338" : "#FAFAFA"
    property color bgSelected: isDarkMode ? "#2A1A3A" : "#F8F0FF"

    property color borderCard: isDarkMode ? "#3A3A3E" : "#E0E0E0"
    property color borderSubtle: isDarkMode ? "#333336" : "#EEEEEE"
    property color borderSep: isDarkMode ? "#2E2E32" : "#F0F0F0"
    property color borderDivider: isDarkMode ? "#3A3A3E" : "#DDDDDD"
    property color borderSelected: isDarkMode ? "#6040A0" : "#D0A0FF"

    property color textTitle: isDarkMode ? "#E8E8E8" : "#1A1A1A"
    property color textPrimary: isDarkMode ? "#D0D0D0" : "#333333"
    property color textSecondary: isDarkMode ? "#A0A0A0" : "#666666"
    property color textMuted: isDarkMode ? "#909090" : "#888888"
    property color textLight: isDarkMode ? "#808080" : "#999999"
    property color textFaint: isDarkMode ? "#707070" : "#AAAAAA"
    property color textDimmed: isDarkMode ? "#606060" : "#BBBBBB"
    property color textPotential: isDarkMode ? "#E0E0E0" : "#2A2A2A"
    property color textDisabled: isDarkMode ? "#666666" : "#999999"
    property color textPlaceholder: isDarkMode ? "#555555" : "#AAAAAA"
    property color listValue: isDarkMode ? "#B3A6C7" : "#7A6090"

    // Text rendered over the statistics detail header image.
    property color detailHeaderTitle: "#FFFFFF"
    property color detailHeaderArtist: isDarkMode ? "#C8C8C8" : "#CCCCCC"
    property color detailHeaderPlayCount: isDarkMode ? "#D8D8D8" : "#CCCCCC"

    property color accent: isDarkMode ? "#B388FF" : "#6A0DAD"
    property color accentHover: isDarkMode ? "#D1B3FF" : "#9D70C9"

    // Settings Specific
    property color divider: isDarkMode ? "#333336" : "#EEEEEE"
    property color settingsTextTitle: isDarkMode ? "#E0E0E0" : "#333333"
    property color settingsTextMuted: isDarkMode ? "#909090" : "#757575"
    property color themeSelectorClear: "#00FFFFFF"
    property color themeSelectorTrack: isDarkMode ? "#242429" : "#E8E9EE"
    property color themeSelectorSelected: isDarkMode ? "#3A3346" : "#FFFFFF"
    property color themeSelectorHover: isDarkMode ? "#11FFFFFF" : "#7AFFFFFF"
    property color themeSelectorText: isDarkMode ? "#9999A2" : "#74747B"
    property color themeSelectorTextSelected: isDarkMode ? "#D1B3FF" : "#6A0DAD"
    
    // Account Connections
    property color arcaeaBg: isDarkMode ? "#2A1A30" : "#F3E5F5"
    property color arcaeaTitle: isDarkMode ? "#CE93D8" : "#6A0DAD"
    property color arcaeaBgOff: isDarkMode ? "#2A2A2E" : "#F0F0F0"
    property color googleBg: isDarkMode ? "#1A2A1E" : "#E8F5E9"
    property color googleTitle: isDarkMode ? "#81C784" : "#2E7D32"
    property color googleBgOff: isDarkMode ? "#2A2A2E" : "#F0F0F0"
    property color titleOff: isDarkMode ? "#A0A0A0" : "#424242"
    property color statusOff: isDarkMode ? "#EF9A9A" : "#E53935"
    
    // Sheet Badges
    property color sheetBadgeBg: isDarkMode ? "#1A2A1E" : "#E8F5E9"
    property color sheetBadgeText: isDarkMode ? "#81C784" : "#2E7D32"
    property color arcaeaBadgeBg: isDarkMode ? "#1A2535" : "#E3F2FD"
    property color arcaeaBadgeText: isDarkMode ? "#64B5F6" : "#1565C0"
    
    // Buttons
    property color btnOpenBg: isDarkMode ? "#1A2A18" : "#F1F8E9"
    property color btnOpenBorder: isDarkMode ? "#558B2F" : "#C5E1A5"
    property color btnOpenText: isDarkMode ? "#A5D6A7" : "#33691E"
    property color btnChangeBg: isDarkMode ? "#333338" : "#F5F5F5"
    property color btnSendBg: isDarkMode ? "#C29EFF" : "#673AB7"
    property color btnSendPressed: isDarkMode ? "#673AB7" : "#5E35B1"
    property color btnDisabled: isDarkMode ? "#555555" : "#B0BEC5"

    // Song DB
    property color dbCardBg: isDarkMode ? "#1A2535" : "#E3F2FD"
    property color dbCardBorder: isDarkMode ? "#1E5580" : "#90CAF9"
    property color dbTitle: isDarkMode ? "#64B5F6" : "#1976D2"
    property color dbBtnBg: isDarkMode ? "#64B5F6" : "#64B5F6"
    
    // Browser
    property color browserBg: isDarkMode ? "#1A2A1E" : "#E8F5E9"
    property color browserBorder: isDarkMode ? "#2E7D32" : "#A5D6A7"
    property color browserTitle: isDarkMode ? "#81C784" : "#2E7D32"
    property color browserDesc: isDarkMode ? "#66BB6A" : "#4CAF50"
    property color browserBtnBg: isDarkMode ? "#FF9800" : "#FF9800"
    
    // Toggle
    property color toggleOn: isDarkMode ? "#B388FF" : "#6A0DAD"
    property color toggleOff: isDarkMode ? "#3A3A3E" : "#E0E0E0"
    property color toggleBorderOff: isDarkMode ? "#555555" : "#CCCCCC"

    // Difficulty Colors
    property color diffPst: isDarkMode ? "#40B8F0" : "#00A0E9"
    property color diffPrs: isDarkMode ? "#70D870" : "#50C050"
    property color diffFtr: isDarkMode ? "#B888FF" : "#A060FF"
    property color diffEtr: isDarkMode ? "#A0A0A0" : "#808080"
    property color diffByd: isDarkMode ? "#F06060" : "#E04040"

    // Score / Potential Colors
    property color scoreFar: isDarkMode ? "#E8B020" : "#E0A000"
    property color scoreLost: isDarkMode ? "#F06060" : "#E04040"

    // Clear range node colors (preserve the pre-dark semantic palette).
    property color clearLost: "#80354A"
    property color clearEasy: isDarkMode ? "#70D870" : "#50C050"
    property color clearComplete: "#A18FA7"
    property color clearHard: "#C2185B"
    property color clearFullRecall: "#F48FB1"
    property color clearPureMemory: "#4AA8A8"
    
    // Ranks
    property color rankGold: isDarkMode ? "#D4B040" : "#C5A028"
    property color rankSilver: isDarkMode ? "#A0A0A0" : "#7A7A7A"
    property color rankBronze: isDarkMode ? "#C06838" : "#A0522D"
    property color rankPurple: isDarkMode ? "#B070E0" : "#984AD0"
    property color bestPotentialMark: isDarkMode ? "#B8B0D0" : "#6A6A8A"

    // Score rank colors
    property color scoreRankPm: isDarkMode ? "#55D6D6" : "#00AAAA"
    property color scoreRankEx: isDarkMode ? "#8E9BFF" : "#5865F2"
    property color scoreRankAa: isDarkMode ? "#D0A0F0" : "#9050B0"
    property color scoreRankLow: isDarkMode ? "#FF7777" : "#D04040"

    // Potential grade colors
    property color potentialTripleStar: isDarkMode ? "#F48FB1" : "#D14A6B"
    property color potentialDoubleStar: isDarkMode ? "#F06292" : "#C12955"
    property color potentialStar: isDarkMode ? "#EF6C75" : "#C62828"
    property color potentialRed: isDarkMode ? "#EF6C75" : "#C62828"
    property color potentialPurple: isDarkMode ? "#CE93D8" : "#8E24AA"
    property color potentialPurpleLow: isDarkMode ? "#BA68C8" : "#AB47BC"
    property color potentialGreen: isDarkMode ? "#81C784" : "#4CAF50"
    property color potentialBlue: isDarkMode ? "#4FC3F7" : "#29B6F6"

    // Diamonds
    property color diamondBg1: isDarkMode ? "#A09040" : "#c2a955"
    property color diamondBorder1: isDarkMode ? "#B8960B" : "#B8860B"
    property color diamondBg2: isDarkMode ? "#7A7D80" : "#8c8f93"
    property color diamondBorder2: isDarkMode ? "#909090" : "#636363"
    property color diamondBg3: isDarkMode ? "#9A5A3A" : "#b16a48"
    property color diamondBorder3: isDarkMode ? "#A06030" : "#8B4513"
    
    // Dots
    property color dotClosed: isDarkMode ? "#FF6B6B" : "#FF6B6B"
    property color dotAnalyzing: isDarkMode ? "#FFB74D" : "#FFB74D"
    property color dotReady: isDarkMode ? "#00FF00" : "#00FF00"
    property color dotInactive: isDarkMode ? "#555555" : "#CCCCCC"
    
    // Diff Cards BG
    property color dcBgPst: isDarkMode ? "#2C3641" : "#F5FCFF"
    property color dcBgPrs: isDarkMode ? "#2C3B2C" : "#F0FFF0"
    property color dcBgFtr: isDarkMode ? "#362C41" : "#F8F0FF"
    property color dcBgByd: isDarkMode ? "#3B2C2C" : "#FFF5F5"
    property color dcBgEtr: isDarkMode ? "#343236" : "#F5F0F5"
    property color dcBgPstSelected: isDarkMode ? "#315164" : "#E3F6FF"
    property color dcBgPrsSelected: isDarkMode ? "#315535" : "#E2F7E2"
    property color dcBgFtrSelected: isDarkMode ? "#503464" : "#F0E3FF"
    property color dcBgBydSelected: isDarkMode ? "#5F3333" : "#FFE3E3"
    property color dcBgEtrSelected: isDarkMode ? "#49404B" : "#EEE5EE"

    // Badges / Misc
    property color badgeBpm: isDarkMode ? "#B388FF" : "#6A0DAD"
    property color badgeLen: isDarkMode ? "#5AA0E8" : "#4A90E2"
    // Preserve the distinct legacy colors for the PM score-tier markers.
    property color frameHighlight: "#5AB8E0"
    property color maxHighlight: "#85D5F5"
    property color bannerFallback: isDarkMode ? "#1A0A28" : "#2A1040"
    property color scrollbar: isDarkMode ? "#7060A0" : "#B090D0"
    property color logBoxBg: isDarkMode ? "#2E2E32" : "#F8F8F8"
    property color logBoxBorder: isDarkMode ? "#333336" : "#EEEEEE"
    property color statusSeparator: isDarkMode ? "#444444" : "#DDDDDD"
    property color gearHoverBg: isDarkMode ? "#3A3A40" : "#E0E0E0"
    property color potentialStarColor: isDarkMode ? "#E05050" : "#C83232"
    property color placeholderBg: isDarkMode ? "#333338" : "#F0F0F0"
    property color placeholderBorder: isDarkMode ? "#3A3A3E" : "#E0E0E0"
    property color thumbPlaceholder: isDarkMode ? "#3A3A40" : "#EEEEEE"

    // Filtered diff cards retain their difficulty tint while clearly reading as disabled.
    // The light palette matches the pre-dark-mode presentation exactly.
    property color dcBgPstFiltered: isDarkMode ? "#29323D" : "#F8FAFA"
    property color dcBgPrsFiltered: isDarkMode ? "#293629" : "#F8FAF8"
    property color dcBgFtrFiltered: isDarkMode ? "#332A3D" : "#FAF8FC"
    property color dcBgBydFiltered: isDarkMode ? "#382A2A" : "#FAF8F8"
    property color dcBgEtrFiltered: isDarkMode ? "#302D33" : "#F8F8F8"
    property color dcBorderPstFiltered: isDarkMode ? "#4D6074" : "#50A0C5"
    property color dcBorderPrsFiltered: isDarkMode ? "#4F6B52" : "#78B078"
    property color dcBorderFtrFiltered: isDarkMode ? "#675274" : "#A080D0"
    property color dcBorderBydFiltered: isDarkMode ? "#755154" : "#C07070"
    property color dcBorderEtrFiltered: isDarkMode ? "#5F5967" : "#909090"
    property color filteredCardStripe: isDarkMode ? "#B6A8C9" : "#000000"
    property real filteredCardStripeOpacity: isDarkMode ? 0.14 : 0.03
    property real filteredCardContentOpacity: isDarkMode ? 0.60 : 0.72

    function getDiffColor(diff) {
        var d = String(diff).toLowerCase();
        if (d === "pst" || d === "past" || d === "0") return diffPst;
        if (d === "prs" || d === "present" || d === "1") return diffPrs;
        if (d === "ftr" || d === "future" || d === "2") return diffFtr;
        if (d === "byd" || d === "beyond" || d === "3") return diffByd;
        if (d === "etr" || d === "eternal" || d === "4") return diffEtr;
        return textMuted;
    }

    function getDiffCardBackground(diff, isSelected, isFiltered) {
        var d = String(diff).toLowerCase();
        if (isFiltered) {
            if (d === "pst" || d === "past" || d === "0") return dcBgPstFiltered;
            if (d === "prs" || d === "present" || d === "1") return dcBgPrsFiltered;
            if (d === "ftr" || d === "future" || d === "2") return dcBgFtrFiltered;
            if (d === "byd" || d === "beyond" || d === "3") return dcBgBydFiltered;
            if (d === "etr" || d === "eternal" || d === "4") return dcBgEtrFiltered;
            return bgCard;
        }

        if (d === "pst" || d === "past" || d === "0") return isSelected ? dcBgPstSelected : dcBgPst;
        if (d === "prs" || d === "present" || d === "1") return isSelected ? dcBgPrsSelected : dcBgPrs;
        if (d === "ftr" || d === "future" || d === "2") return isSelected ? dcBgFtrSelected : dcBgFtr;
        if (d === "byd" || d === "beyond" || d === "3") return isSelected ? dcBgBydSelected : dcBgByd;
        if (d === "etr" || d === "eternal" || d === "4") return isSelected ? dcBgEtrSelected : dcBgEtr;
        return bgCard;
    }

    function getFilteredDiffCardBorder(diff) {
        var d = String(diff).toLowerCase();
        if (d === "pst" || d === "past" || d === "0") return dcBorderPstFiltered;
        if (d === "prs" || d === "present" || d === "1") return dcBorderPrsFiltered;
        if (d === "ftr" || d === "future" || d === "2") return dcBorderFtrFiltered;
        if (d === "byd" || d === "beyond" || d === "3") return dcBorderBydFiltered;
        if (d === "etr" || d === "eternal" || d === "4") return dcBorderEtrFiltered;
        return borderDivider;
    }
    
    function getRankColor(rank) {
        var r = String(rank || "").toLowerCase();
        if (r === "pm") return scoreRankPm;
        if (r === "ex+" || r === "ex") return scoreRankEx;
        if (r === "aa" || r === "a") return scoreRankAa;
        if (r === "b" || r === "c" || r === "d") return scoreRankLow;
        return textSecondary;
    }

    function getPotentialRankColor(rank) {
        var n = Number(rank);
        if (!isFinite(n) || n <= 0) return textSecondary;
        if (n === 1) return rankGold;
        if (n === 2) return rankSilver;
        if (n === 3) return rankBronze;
        return rankPurple;
    }

    function getPotentialColor(rating) {
        if (rating === undefined || rating === null || isNaN(Number(rating))) return textMuted;
        var p = Number(rating);
        if (p >= 1300) return potentialTripleStar;
        if (p >= 1250) return potentialDoubleStar;
        if (p >= 1200) return potentialStar;
        if (p >= 1100) return potentialRed;
        if (p >= 1000) return potentialPurple;
        if (p >= 700) return potentialPurpleLow;
        if (p >= 300) return potentialGreen;
        return potentialBlue;
    }
    

    // Additional alpha masks and shadows
    property color mask10: isDarkMode ? "#1A1A1A1E" : "#1AFFFFFF"
    property color mask20: isDarkMode ? "#331A1A1E" : "#33FFFFFF"
    property color mask35: isDarkMode ? "#591A1A1E" : "#59FFFFFF"
    property color mask40: isDarkMode ? "#661A1A1E" : "#66FFFFFF"
    property color mask50: isDarkMode ? "#801A1A1E" : "#80FFFFFF"
    property color mask65: isDarkMode ? "#A61A1A1E" : "#A6FFFFFF"
    property color mask70: isDarkMode ? "#B31A1A1E" : "#B3FFFFFF"
    property color mask80: isDarkMode ? "#CC1A1A1E" : "#CCFFFFFF"
    property color mask88: isDarkMode ? "#E01A1A1E" : "#E0FFFFFF"
    property color mask90: isDarkMode ? "#E61A1A1E" : "#E6FFFFFF"
    property color mask92: isDarkMode ? "#EB1A1A1E" : "#EBFFFFFF"
    property color mask94: isDarkMode ? "#F01A1A1E" : "#F0FFFFFF"
    property color mask96: isDarkMode ? "#F51A1A1E" : "#F5FFFFFF"
    property color mask98: isDarkMode ? "#FA1A1A1E" : "#FAFFFFFF"
    property color mask100: isDarkMode ? "#FF1A1A1E" : "#FFFFFFFF"
    
    property color shadowLight: isDarkMode ? "#80000000" : "#40000000"
    property color shadowNormal: isDarkMode ? "#C0000000" : "#80000000"
    
    property color overlay: isDarkMode ? "#C0000000" : "#80000000"
    property color overlayDark: isDarkMode ? "#E0000000" : "#E0333333"
    property color overlayDarker: isDarkMode ? "#E6000000" : "#E6222222"
    property color overlayLight: isDarkMode ? "#D01A1A1E" : "#D0FFFFFF"
    property color overlayText: isDarkMode ? textTitle : bgCard
    
    property color dbBtnBgDown: isDarkMode ? "#1E88E5" : "#42A5F5"
    property color browserBtnBgDown: isDarkMode ? "#F57C00" : "#43A047"
    property color hoverOverlay: isDarkMode ? "#1AFFFFFF" : "#EFEFEF"
    
    property color borderOverlay: isDarkMode ? "#331A1A1E" : "#33FFFFFF"

}
