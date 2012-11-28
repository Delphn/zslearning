function [ data, categories, categoryNames ] = loadBatch( prefix, cifar_dir, batch )

if nargin < 3
    t = load([cifar_dir sprintf('/%s.mat', prefix)]);
else
    t = load([cifar_dir sprintf('/%s_%d.mat', prefix, batch)]);
end

data = t.X;
categories = t.Y;
categoryNames = t.names;
clear t;

end
