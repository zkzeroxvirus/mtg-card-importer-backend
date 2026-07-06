const THEME_COLOR_TEXT_REGEX = /^\(theme color:/i;

function hasAnyLegalFormat(card) {
  return Object.values(card?.legalities || {}).some(status => status === 'legal');
}

function hasRelatedGameplaySource(card) {
  return Array.isArray(card?.all_parts) && card.all_parts.length > 0;
}

function hasMeaningfulRulesText(card) {
  const oracleText = String(card?.oracle_text || '').trim();
  if (oracleText && !THEME_COLOR_TEXT_REGEX.test(oracleText)) {
    return true;
  }

  return Array.isArray(card?.card_faces) && card.card_faces.some(face => {
    const faceText = String(face?.oracle_text || '').trim();
    return faceText && !THEME_COLOR_TEXT_REGEX.test(faceText);
  });
}

function isStandaloneNonGameplayCard(card) {
  const typeLine = String(card?.type_line || '').trim().toLowerCase();
  const genericCardType = typeLine === 'card' || typeLine === 'card // card';

  return genericCardType &&
    !hasAnyLegalFormat(card) &&
    !hasRelatedGameplaySource(card) &&
    !hasMeaningfulRulesText(card);
}

module.exports = {
  hasAnyLegalFormat,
  hasRelatedGameplaySource,
  hasMeaningfulRulesText,
  isStandaloneNonGameplayCard
};
