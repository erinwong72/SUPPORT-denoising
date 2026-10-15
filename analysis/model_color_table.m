function colors = model_color_table(n)
%MODEL_COLOR_TABLE  n x 3 line colors: row 1 is raw (gray), rows 2.. one per model.
% The first four rows are the original fixed colors; more rows are added as needed,
% so any number of models works.
base = [0.35 0.35 0.35;   % raw
        0.85 0.33 0.10;
        0.00 0.45 0.74;
        0.55 0.15 0.85;
        0.93 0.69 0.13;
        0.10 0.60 0.30;
        0.85 0.10 0.50;
        0.30 0.75 0.93;
        0.64 0.08 0.18;
        0.50 0.50 0.00];
if n <= size(base, 1)
    colors = base(1:n, :);
else
    extra = hsv(n - size(base, 1) + 1);   % +1 so the last hue is not a repeat of the first
    colors = [base; extra(1:end-1, :) * 0.85];
end
end
