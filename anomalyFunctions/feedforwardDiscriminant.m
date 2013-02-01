function [guessedLabels] = feedforwardDiscriminant(thetaMapping, thetaSoftmax, trainParams, smTrainParams, unseenWordTable, images, maxLogprobability, zeroCategoryTypes, nonzeroCategoryTypes, mu, sigma, priors)

[ W, b ] = stack2param(thetaMapping, trainParams.decodeInfo);

% Forward Propagation
mappedImages = bsxfun(@plus, 0.5 * W{1} * images, b{1});

logprobabilities = predictGaussianDiscriminant(mappedImages, mu, sigma, priors, zeroCategoryTypes);
unseenIndices = logprobabilities < maxLogprobability;
seenIndices = ~unseenIndices;

Ws = stack2param(thetaSoftmax, smTrainParams.decodeInfo);
pred = exp(Ws{1}*images(:, seenIndices)); % k by n matrix with all calcs needed
pred = bsxfun(@rdivide,pred,sum(pred));
[~, gind] = max(pred);
guessedLabels(seenIndices) = nonzeroCategoryTypes(gind);

% This is the unseen label classifier
tDist = slmetric_pw(unseenWordTable, mappedImages(:, unseenIndices), 'eucdist');
[~, tGuessedCategories ] = min(tDist);
guessedLabels(unseenIndices) = zeroCategoryTypes(tGuessedCategories);

end
