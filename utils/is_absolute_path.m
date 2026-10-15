function tf = is_absolute_path(p)
%IS_ABSOLUTE_PATH  True for Unix absolute, Windows drive, or UNC paths.
tf = startsWith(p, '/') || startsWith(p, '\') || ...
    (~isempty(regexp(p, '^[A-Za-z]:', 'once')));
end
