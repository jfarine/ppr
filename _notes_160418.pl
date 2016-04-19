Logique ppr.pl - Dégrossissage

160418 JF

1. Par ordre inverse d'apparition, les tests importants:

Une nouvelle crue est établie quand $new_spate=1 :

lignes 893++   
            if($in_spate && !$in_spate_last 
                         && !$in_spate_last_but1 
                         && !$in_spate_last_but2){
                $new_spate=1;
                
Un point de donnée est dit en condition de crue $in_spate, si:

lignes 885++
            if($sum >= $n_slope_up_above_thres && $last_thres_vals[0] == 1 
                         && $last_thres_vals[$n_recent_to_consider-1] == 1
                         && $dq_local >= $dq_local_min){
                $in_spate=1;

Il y a 6 variables ou vectors à comprendre :

- $sum est la somme de flags aux lignes 871++:
            $sum=0;
            for($i=0;$i<$n_recent_to_consider;$i++){
                $sum += $last_thres_vals[$i];
            }
    où @last_thres_vals est un vecteur rempli à la ligne 823 (note: qui est après la condition $ndata>1):
                push(@last_thres_vals, $above_thres);  [v. point 2.]
    où $above_thres est assigné aux lignes 808++:
        if($dqdt_qpm > $spate_thres_up) {
            $above_thres = 1;
    et $dqdt_qpm est la variation temporelle dqdt calculée depuis le dernier point et
    exprimée en unité de "quantité" par minute;
    finalement, $space_thres_up est un paramètre de reglage défini dans le fichier DB:
    c'est le taux de variation de la quantité qui est considéré comme seuil: toute valeur
    en dessus de ce seuil indique une forte probabilité qu'une crue est engagée ou en cours.
    Il est donc impératif de donner une valeur de $space_thres_up en quantité par minute.

- $n_slope_up_above_thres est aussi un paramètre de la DB, critère à remplir pour se trouver en
condition de crue: 
# number of data points in the $n_recent_to_consider  most recent that must be above threshold 

- $last_thres_vals est discuté en dessus; le vecteur contient l'historique récent des conditions
en dessus du seuil

- $n_recent_to_consider  est aussi un paramètre de la DB:
# number of consecutive data points that must be looked at for being above threshold or not 
(ces points sont ceux qui précèdent directement le point courant)

- $dq_local est une valeur calculée aux lignes 877++:
            if($ndata > $n_recent_to_consider){             #BUG-R# (took off the "+3" on 160417 that was in there)  ### MUST CHECK ###
                # $dq_local = 1000.*($dq_local_vals[$n_recent_to_consider]-$dq_local_vals[0]);  ### 1000 multipliers was to get mm, removed 160417  ### MUST CHECK ###
                $dq_local = ($dq_local_vals[$n_recent_to_consider]-$dq_local_vals[0]);
            }
  C'est le fameux cas où il y avait autrefois un +3 (qui reste à comprendre).
  Il faut noter que sans le +3, le test est redondant au test d'entrée dans ce bloc, ligne 861
  
  Le vecteur @dq_local_vals est en fait l'historique de la "quantité" (Q ou T, autrefois le niveau), 
  enregistré à la ligne 653 (note: qui est avant la condition $ndata>1):
  	  push(@dq_local_vals, $qty);   [v. point 2.]

- finalement, $dq_local_min est aussi un paramètre de la DB, critère à remplir pour se trouver en
condition de crue:
#   $dq_local_min             = min raise requested 


2. Manipulations des vecteurs incriminés par push() en début de bloc, et shift() en fin.

Par bloc j'entends les déclarations entre la lecture d'un nouveau point de donnée et la
lecture du suivant.

Dans la première partie, certaines composantes des vecteurs sont utilisées pour les décisions,
ces composantes ne sont pas forcément la valeur courante ou celle au début de la période
"histoire récente" définie par $n_recent_to_consider.

Il est primordial de comprendre comment les vecteurs sont manipulés pour comprendre quelles
valeurs, courantes ou historiques, font partie des décisions si une crue est en cours ou non.

En particulier, ces deux vecteurs sont initialisés ainsi:
  	  push(@dq_local_vals, $qty);  - dès $ndata = 1
      alors que push(@last_thres_vals, $above_thres); - dès $ndata > 1,
pour la simple raison que la notion de seuil est liée à une variation de quantité et 
qu'il faut deux points pour la calculer.

Le point clé est qu'ils ne commencent pas à être remplis (avec push(), à droite 1) en meme 
temps. Par contre ils sont vidés en meme temps (avec shift(), à gauche 1). Leur longeur 
va donc toujours différer d'une unité.

[ 1) L'extrait suivant de "Learning Perl, 6th edition, p.50" résume l'essentiel des functions
utilisées ici, push() et shift():

The push and pop operators do things to the end of an array (or the right side of an array,
or the portion with the highest subscripts, depending upon how you like to think of
it). Similarly, the unshift and shift operators perform the corresponding actions on
the “start” of the array (or the “left” side of an array, or the portion with the lowest
subscripts). ]

Les boucles principales peuvent être résumées ainsi:

# loop over input data
while(<IDF>) {
	  push(@dq_local_vals, $qty);  
    if($ndata > 1){
        push(@last_thres_vals, $above_thres);
        if($ndata > $n_recent_to_consider) {
            ... utilisation des vecteurs ...
            shift(@last_thres_vals);
            shift(@dq_local_vals);
        } # if ndata > n_recent_to_consider
        ... plein d'autres choses se passent  
    } # ndata > 1
    ... et ici encore  
} # while (<IDF>) -- loop over data lines in .tod file
    
En conséquence, le vecteur @dq_local_vals aura toujours:
- à l'index $n_recent_to_consider : la valeur du point courant
- à l'index 0: la valeur du "$n_recent_to_consider"-nième point en arrière

Alors que les vecteurs qui ne sont initialisés que a partir de $ndata>1, tel que 
@last_thres_vals, auront:
- à l'index ($n_recent_to_consider)-1 : la valeur du point courant
- à l'index 0: la valeur du "($n_recent_to_consider)-1"-nieme point en arriere


3. Algorythme de détection des crues et des pics

... plus le temps (c'est déjà minuit 40 ..) ... mais en gros:

- les critères actuels comparent le point courant avec "un autre point dans le passé récent"
- quand ça a marché c'était plutôt du bol
- certains calculs sur plusieurs poitns récents sont justifiés et corrects
- il faut se plonger dans le détail de l'utilisation de tel ou telle valeur dans le passé,
et une fois qu'elle est documentée, se demander quelle approche est la meilleures (et selon
quels critères), puis programmer la réponse !







      