% SETUP - Inizializza l'ambiente per FSDA Table Interface
% Esegui questo script una volta all'apertura di MATLAB

disp('--- FSDA Table Interface Setup ---');

% Ottieni il percorso della cartella dove si trova questo script
rootFolder = fileparts(mfilename('fullpath'));

% Aggiungi le sottocartelle al percorso di MATLAB
% genpath include ricorsivamente tutte le sottocartelle (src, safe_methods, examples)
addpath(genpath(rootFolder));

fprintf('Path aggiornato correttamente.\n');
fprintf('Sottocartelle incluse:\n - src\n - safe_methods\n - examples\n');
disp('----------------------------------');