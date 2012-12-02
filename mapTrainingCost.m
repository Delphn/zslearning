function [cost, grad] = mapTrainingCost( theta, data, params )

[ W, b ] = stack2param(theta, params.decodeInfo);

numImages = size(data.imgs, 2);
allImgs = [ data.imgs data.zeroimgs ];
numAllImages = size(allImgs, 2);

a2All = params.f(bsxfun(@plus, W{1} * allImgs, b{1}));
hAll = bsxfun(@plus, W{2} * a2All, b{2});
w = params.f(data.wordTable(:, data.categories));
a2 = a2All(:, 1:numImages);

lambda = params.lambda;
reg = 0.5 * lambda * (sum(sum(W{1} .^ 2)) + sum(sum(W{2} .^ 2)) + sum(b{1} .^ 2) + sum(b{2} .^ 2));
cost = 0.5 * (1 / numImages * sum(sum((w - a2).^2)) + params.autoencMult / numAllImages * sum(sum((hAll-allImgs).^2))) + reg;

% Find error signal terms
del3All = params.autoencMult * (hAll - allImgs) / numAllImages;
del2All = W{2}' * del3All .* params.f_prime(a2All);
del2 = (a2 - w) / numImages .* params.f_prime(a2);

% Calculate gradients
W2grad = del3All * a2All' +  + lambda * W{2};
b2grad = sum(del3All, 2) + lambda * b{2};
W1grad = del2 * data.imgs' + del2All * allImgs' + lambda * W{1};
b1grad = sum(del2, 2) + sum(del2All, 2) + lambda * b{1};

grad = [ W1grad(:); W2grad(:); b1grad(:); b2grad(:) ];

if params.doEvaluate == true
    doPrint = true;
    mapDoEvaluate(data.imgs, data.categories, data.categoryNames, data.categoryNames, data.wordTable, theta, params, doPrint);
    mapDoEvaluate(data.validImgs, data.validCategories, data.categoryNames, data.categoryNames, data.wordTable, theta, params, doPrint);
    mapDoEvaluate(data.testImgs, data.testCategories, data.testOriginalCategoryNames, data.testCategoryNames, data.testWordTable, theta, params, doPrint);
end

end
