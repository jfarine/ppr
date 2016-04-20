Logique ppr.pl - Dégrossissage

160418+9 JF

Il y a deux catégories de tests. Elles sont indépendantes. La première détecte l'apparition
d'une nouvelle crue, puis en détermine le moment et le niveau de base. La seconde détecte le
pic et le point bas qui en découlent (et leur moment et leur valeur). Les deux catégories
utilisent la meme notion de "pente seuil" pour déterminer si un acroissement de la quantité 
a lieu. **Deux variables différentes ($spate_thres_up et $thres_up) paramétrisent cette pente
séparément dans chaque catégorie**. Ceci est voulu, pour éviter toute interférence. Car rien 
n'indique à priori que les pentes seuil seront les memes pour les conditions cherchant à 
détecter un début de crue ou un pic de crue, deux événements différents. P. ex., le code
actuel utilise la pente seuil de pic, $thres_up, pour trouver le premier point où la
pente est descendue en dessous de cette valeur. 

Les deux catégories sont discutées separément dans cette note, qui regarde d'abord le
code brut (pour ne pas faire d'erreur dinterprétation - section 1). Vient ensuite une
note sur la manipulation des vecteurs avec push() et shift() (section 2). Cette section
est la clé de toute la logique du script ! Un résumé de la logique en mots  est donné
ensuite (section 3). La section 4 propose une modification de code
pour soft-coder un critère actuellement en dur, et la section 5 atire l'attention sur
un aspect négligé du code, qui pourrait causer problème. Finalement, la section 6 groupe
quelques todoes.

Les no. de ligne valent pour la version GitHub de ppr.pl du 160417.


1. Par ordre inverse d'apparition, les tests importants en code brut

1.A Une nouvelle crue est établie quand $new_spate=1 :

lignes 893++   [[ new_spare condition ]]
            if($in_spate && !$in_spate_last 
                         && !$in_spate_last_but1 
                         && !$in_spate_last_but2){
                $new_spate=1;

Note: cette condition veut imposer un certain délai entre crues: elle exige qu'il y ait 
trois points, à la suite et précédant le point courant, qui ne soient *pas* en condition
de crue avant qu'une nouvelle crue puisse être déclarée. Elle diminue le nombre de crues
trouvées dans un signal bruité.

Un point de donnée est dit en condition de crue $in_spate, si:

lignes 885++  [[ in_spate condition ]]
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
                push(@last_thres_vals, $above_thres);  [v. section 2]
    où $above_thres est assigné aux
    
lignes 808++: [[ above_thres condition ]]
        if($dqdt_qph > $spate_thres_up) {         # note: corrigé _qpm > _qph by CV 160419
            $above_thres = 1;
            
    et $dqdt_qph est la variation temporelle dqdt calculée depuis le dernier point et
    exprimée en unité de "quantité" par heure;
    finalement, $space_thres_up est un paramètre de reglage défini dans le fichier DB:
    c'est le taux de variation de la quantité qui est considéré comme seuil: toute valeur
    en dessus de ce seuil indique une forte probabilité qu'une crue est engagée ou en cours.
    Il est donc impératif de donner une valeur de $space_thres_up en quantité par heure.

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
  	  push(@dq_local_vals, $qty);   [v. section 2]

- finalement, $dq_local_min est aussi un paramètre de la DB, critère à remplir pour se trouver en
condition de crue:
#   $dq_local_min             = min raise requested 

1.B. Détection du pic / creux de la crue

1.B.1. Un pic (peak) est détecté quand $is_max=1 

lignes 1063++  [[ is_max "peak condition" ]]
            if($dqdt_qph <= $thres_up && $peak_cond_met == 1 
                                      && $nspate > 0){
                printf (STDOUT " passed ++++++") if ($verbose);
                $is_max=1;

    et la variable $peak_cond_met est établie par:
    
lignes 1052++  [[ peak_cond_met condition ]]
            $peak_cond_met=1;  ## 160418 JF: a bit of a misnomer: this is saying "all 
            # points so far are still going up" - a condition to be met up to the peak
            # important: do *not* use current point ! we want it have a neg slope so peak is hard-coded  @ last point ..
            # yes, yes, yes.. # array elements increased in test above, hence no '-1' below (and line above still holds)
            for($i=0;$i<$n_thres_up;$i++){
                $peak_cond_met *= $last_slopeup_vals[$i];
            }

    - et en remontant la chaîne:
lignes 846
        push(@last_slopeup_vals, $up_met);
lignes 839++
        if($dqdt_qph > $thres_up) {
            $up_met = 1;
        } else {
            $up_met = 0;
        }
    - $thres_up est un paramètre de la DB, le pendant de $spate_thres_up pour les pics
    - $n_thres_up est un paramètre de la DB, le nombre à considérer, le pendant de 
      $n_slope_up_above_thres pour les pics
      Ce paramètre n'est utilisé que dans la boucle de $peak_cond_met, et dans la
      condition (évidente) qu'il faut avoir assez de points pour l'utiliser:
ligne 1048:
        if($ndata > $n_thres_up+1) {

1.B.2. Un creux (through) est détecté quand $is_min=1 

À quelques détails près, le code pour détecter un creux est identique au code pour détecter
un pic, mais en substitutant les variables "_ip" avec des variables "_dn"

Mais voir la section 5: l'éléphant dans la pièce !!!



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

Les boucles principales peuvent être                # Tableau de progression de l'index maximum des deux stacks en
résumées ainsi:                                     # fonction de $ndata ($n_recent_to_consider=4, $n_not_in_spate_req=3)
                                                    #  __dq_local_vals__   __last_thres_vals__   __last_in_spate_vals__            
# loop over input data                       $ndata =  1 2 3 4 5 6 7 8 9    1  2 3 4 5 6 7 8 9    1  2  3  4  5 6 7 8 9
while(<IDF>) {                                      # -1 0 1 2 3 3 3 3 3   -1 -1 0 1 2 2 3 3 3   -1 -1 -1 -1 -1 0 1 2 2   
	  push(@dq_local_vals, $qty);                     #  0 1 2 3 4 4 4 4 4   -1 -1 0 1 2 2 3 3 3   -1 -1 -1 -1 -1 0 1 2 2            
    if($ndata > 1){                                 #  - 1 2 3 4 4 4 4 4    - -1 0 1 2 2 3 3 3    - -1 -1 -1 -1 0 1 2 2             
        push(@last_thres_vals, $above_thres);       #  - 1 2 3 4 4 4 4 4    -  0 1 2 3 3 3 3 3    -  - -1 -1 -1 0 1 2 2       
        if($ndata > $n_recent_to_consider) {        #  - - - - 4 4 4 4 4    -  - - - 3 3 3 3 3    -  -  -  - -1 0 1 2 2          
            ... utilisation des @dq, thres ...  --->#  - - - - 4 4 4 4 4    -  - - - 3 3 3 3 3<-- -  -  -  - -1 0 1 2 2        
            push(@last_in_spate_vals, $in_spate);   #  - - - - 4 4 4 4 4    -  - - - 3 3 3 3 3    -  -  -  -  0 1 2 3 3    
            if($ndata > $n_recent_to_consider
                        +$n_not_in_spate_req) {     #  - - - - - - - 4 4    -  - - - - - - 3 3    -  -  -  -  - - - 3 3
                ..utilisation du @last_in_spate..-->#  - - - - - - - 4 4    -  - - - - - - 3 3    -  -  -  -  - - - 3 3<--
                shift(@last_in_spate_vals);         #  - - - - - - - 4 4    -  - - - - - - 3 3    -  -  -  -  - - - 2 2  
            }                                       #                                          
            shift(@last_thres_vals);                #  - - - - 4 4 4 4 4    -  - - - 2 2 2 2 2    -  -  -  -  0 2 2 2 2
            shift(@dq_local_vals);                  #  - - - - 3 3 3 3 3    -  - - - 2 2 2 2 2    -  -  -  -  0 2 2 2 2
        } # if ndata > n_recent_to_consider                                               
        ... plein d'autres choses se passent        #  - 1 2 3 3 3 3 3 3    -  0 1 2 2 2 2 2 2    - -1 -1 -1  0 2 2 2 2
    } # ndata > 1
    ... et ici encore                               #  0 1 2 3 3 3 3 3 3   -1  0 1 2 2 2 2 2 2   -1 -1 -1 -1  0 2 2 2 2   
} # while (<IDF>) -- loop over data lines in .tod file
    
En conséquence, le vecteur @dq_local_vals aura toujours:
- à l'index max [$n_recent_to_consider] : la valeur du point courant
- à l'index min [0] : la valeur du "$n_recent_to_consider"-nième point dans le passé

Alors que les vecteurs qui ne sont initialisés que a partir de $ndata>1, tel que 
@last_thres_vals, auront:
- à l'index max [($n_recent_to_consider)-1] : la valeur du point courant
- à l'index min [0] : la valeur du "($n_recent_to_consider)-1"-nieme point dans le passé

Conséquences:
a. c'est pour ça que dans la condition "in_spate", le '-1' apparait dans
   $last_thres_vals[$n_recent_to_consider-1] - c'est le point courant !
b. c'est une erreur d'utiliser l'index [$n_recent_to_consider] pour tout vecteur
   manipulé par push/shift sauf ceux initialisés avant 'if($ndata>1)' comme  @dq_local_vals

Note rajoutée le 160419JF: la modif de code de la section 4 va rajouter un nouveau stack
encore plus petit, @last_in_spate_vals .. meme principes, voir Tableau rajouté le 160420.


3. Algorithme de détection des crues et des pics

... plus le temps (c'est déjà minuit 40 ..) ... mais en gros:

- les critères actuels comparent le point courant avec "un autre point dans le passé récent"
- quand ça a marché c'était plutôt du bol
- certains calculs sur plusieurs poitns récents sont justifiés et corrects
- il faut se plonger dans le détail de l'utilisation de tel ou telle valeur dans le passé,
et une fois qu'elle est documentée, se demander quelle approche est la meilleures (et selon
quels critères), puis programmer la réponse !

[ Retour le 160419 AM ]

En résumé, l'algorithme actuel, en mots :

Sauf indication du contraire, il est admis dans ce qui suit que toutes les sous-conditions
listées sous une condition doivent être vérifiées (&&) pour que cette condition soit vérifiée.
La syntaxe:
[[ name condition ]]
- A
- B
implique: $name = 1 if (A && B)

3.A. Détection d'une nouvelle crue 

[[ new_spate condition ]]
- le point courant est in_spate
- mais pas le point avant (last)
- ni celui avant (last but 1)
- ni celui avant (last but 2)

# Comme c'est là, cette condition de "3 avant pas en crue" est hard-coded. En fait, tout est
# déjà prévu dans la DB: il y a une variable inutilisée $n_not_in_spate_req, qui a été 
# introduite exactement pour soft-coder ce test ! Il suffit d'écrire le code. Voir section 4.

[[ in_spate condition ]]
- au moins ($n_slope_up_above_thres) des ($n_recent_to_consider) derniers points sont $above_thres
- le ($n_recent_to_consider-1)-nième point avant le courant (index [0]) était $above_thres 
- le point courant (index [$n_recent_to_consider-1]) est $above_thres 
- la différence de quantité entre :
  le ($n_recent_to_consider)-nième point avant le courant (index [0])
  et
  le point courant (index [$n_recent_to_consider])
  est plus élevée que $dq_local (PARAM DB)  - c'est un des "seuils", celui-ci en unité "quantité"
  
[[ above_thres condition ]]
- le taux de variation de la quantité exprimée en "quantité par heure", dqdt_qph 
  est plus élevé que $spate_thres_up (PARAM DB) - c'est un des "seuils", unité "quantité par heure"

Points saillants:
- l'intervale de points récents considéré est défini par $n_recent_to_consider
- la variable $sum évalué $above_thres sur *tous* les points de l'intervale
- son utilisation est paramétrée et permet de tenir compte de ce qui se passe durant cet intervale  
- sinon, seules les valeurs au début de l'intervale et la valeur courante sont utilisées
  dans les tests -- ** aucune des valeurs intermédiaires **
- il y a donc un peu de redondance - voulue - dans l'utilisation de $above_thres sur
  l'intervale:
  - à la fois on demande un certain nombre en dessus d'un certain seuil sur tout l'intervale
    sans être plus spécifique - l'aspect plus libre aide à filter le bruit
  - et en meme temps on exige strictement que le point au début et le point (courant) à la 
    fin de l'intervale soient $above_thres. Cette exigence évite en fait les situations où
    une crure pourrait être déclarée uniquement sur le premier critère et moins de points,
    du type 0-1-...-1-0. Des tests ont montré que sans cette dernière exigence, plus de
    crues sont "détectées" où il n'y en a en fait pas.

3.B. Détection du pic et point bas (peak/through) de cette nouvelle crue

3.B.1. [[ peak condition ]]
- la pente $dqdt_qphest sous le seuil $thres_up (note: pas le meme seuil que en A!)


4. Proposition de modif de code

Voir section 3.A.: soft-coding du nombre de points "not in spate" à exiger avant de déclarer
une nouvelle crue.

Problématique:
- définition/disponibilité des variables
  - utiliser la variable $n_not_in_spate_req qui est déjà dans la DB (et initialisée à 3, 
    correspondant à l'usage actuel "hard-coded")
- retard dans la détection de crue
  - $in_spate n'est pas mémorisée dans un stack pour l'instant
  - $in_spate est calculée juste avant de tester $new_spate
  - il faut avoir déjà calculé $in_spate pour un nombre de points $n_not_in_spate_req avant 
    de pouvoir tester $new_spate
  - et $in_spate n'est vraiment calculé pour la première fois que au point de donnée
    No ($n_recent_to_consider)+1 !! (ex: au 11e point quand on met cette variable à 10)
    [j'ai vérifié avec le code réel]
  - ensuite, il faut encore $n_not_in_spate_req points de plus avant de tester pour une
    nouvelle crue. Si cette variable est =3 comme dans la DB actuelle (en accord avec le code),
    alors on ne peut tester pour une nouvelle crue que au 14e point (14 = 10+3+1). 
    Ça peut représenter 14 heures si $ST = 60 min! J'assume que c'est ça qu'on veut.
- définition/disponibilité des variables (bis)
  - il faut un stack pour $in_spate
  - ce stack doit contenir $n_not_in_spate_req valeurs
  -> il faut donc:
      - immédiatement ajouter $in_spate à un stack dès qu'elle est obtenue
        push(@last_in_spate_vals, $in_spate);
      - mais attendre encore $n_not_in_spate_req points avant de procéder au test
        => nouveau bloc if($ndata > $n_recent_to_consider+$n_not_in_spate_req) {
      - donc n'utiliser shift() que après avoir attendu ces points, donc dans le scope
        et à la fin de ce nouveau bloc if(){}
      - récrire le test pour $new_spate (dans ce nouveau bloc)
      - garder tout le code des conséquences du test $new_spate dans ce nouveau bloc
And that pretty much cuts it.

Quick index check - with this scheme, and redefining for convenience:
n = $ndata
N = $n_recent_to_consider
M = $n_not_in_spate_req
then:
last_in_spate_vals[0]   = value of $in_spate for data point "current-M"
last_in_spate_vals[M-1] = value of $in_spate for data point "last"
last_in_spate_vals[M]   = value of $in_spate for data point "current"
[ I made the same Table as at the bottom of p.5 of today's flowchart.PDF to find this out ]

Donc - proposition de modification:

Attention ! Les Nos de ligne **vont** changer, mettre des balises avant de modifier !

i) À la ligne 885, remplacer:
            if($sum >= $n_slope_up_above_thres && $last_thres_vals[0] == 1 
                         && $last_thres_vals[$n_recent_to_consider-1] == 1
                         && $dq_local >= $dq_local_min){
                $in_spate=1;
            } else {
                $in_spate=0;
            }
            ##### check if new spate ###  remember data now goes *forward* in time
            if($in_spate && !$in_spate_last 
                         && !$in_spate_last_but1 
                         && !$in_spate_last_but2){
                         # && $n_not_above_thres >= $n_not_above_thres_req) {
                $new_spate=1;
par:
            if($sum >= $n_slope_up_above_thres && $last_thres_vals[0] == 1 
                         && $last_thres_vals[$n_recent_to_consider-1] == 1
                         && $dq_local >= $dq_local_min){
                $in_spate=1;
            } else {
                $in_spate=0;
            }
            push(@last_in_spate_vals, $in_spate);
            # must wait enough additional points are collected, so that one can test
            # according to parametrization in DB
            if($ndata > $n_recent_to_consider+$n_not_in_spate_req) {
                # sum over recent (but not current!) points, to check that they were *not* in_spate
                $sum_ris=0;
                for($i=0;$i<$n_not_in_spate_req;$i++){
                    $sum_ris += $last_in_spate_vals[$i];
                }
                # i.e. $sum_ris should remain 0 if none of them was in_spate
                ##### check if new spate ###  remember data now goes *forward* in time
                if($in_spate && $sum_ris == 0) {
                    $new_spate=1;

ii) shifter tout le bloc entre $new_spate=1; et $last_spate_epoch=$epoch_base;
    de 4 espaces vers la droite (voir ci-dessous)
    
iii) à la ligne (actuelle) 977, remplacer:
                $last_spate_epoch=$epoch_base;
            } # if newspate
            # safer now to clean arrays at the bottom
            shift(@last_thres_vals);
par:
                    $last_spate_epoch=$epoch_base;
                } # if newspate
                shift(@last_in_spate_vals);
            } # if($ndata > $n_recent_to_consider+$n_not_in_spate_req)
            # safer now to clean arrays at the bottom
            shift(@last_thres_vals);

C'est tout ! À tester bien sur :-)




5. L'éléphant dans la pièce

Un aspect est discuté nulle part et n'a pas reçu beaucoup d'attention lors du développement
du script d'origine cl2dat.pl (ou alors j'ai oublié) : c'est comment la détection d'un
creux (through) n'entre pas en conflit avec la détection de la crue suivante. Le détecteur
de creux pourrait théoriquement casser tout le code: une fois le creux proprement détecté,
c'est trop tard pour chercher une nouvelle crue, elle a déjà commencé.

Une indication serieuse qu'il faut passer cette section du code sous la loupe est que la doc fait 
souvent référence à la détection de creux en disant "comme pour les pics mais avec ses 
propres variables _dn au lieu de _up". Il y a peut-être des bugs.. j'ai flaggé des
passages qui utilisent une variable "peak" ou j'attendais "through", et j'ai vu un 
"_dn" ou j'attendais un "_up" sur cette meme ligne.

Je laisse celà pour la prochaine étape.. [160419]

REMARQUE IMPORTANTE: Ne pas tuer le bébé éléphant !!! 

Dans la recherchede pic, quand un pic est trouvé, la routine setmin(); est invoquée.
Ce n'est pas un bug !!! Le code cherche sans répit, en général, des points max et min. 
Ces recherches doivent être initialisées: "le minimum .. depuis quand ?"
L'initialisation d'une recherche de minimum *doit* se faire au
point le plus haut, car à partir de là "ça ne peut que descendre", jusqu'à ce qu'on trouve 
ce minimum. 

La meme discussion s applique pour l'invocation de setmax() quand un creux est trouvé. 


6. TODOes au 160419
nettoyages finaux:
- tous les formats output:
  - ODDF mis en ordre par CV (pour matlab)
  - ODF (excel)
  - STDOUT (pour humains, consommation immédiate)
  - ODSLF (fichier .sptl ou .spate-long, pour humains)
    => attention, les indices [0] sont actuellement imprimés. C'est incorrect car le [0]
       dépend des params dans la DB ! C'est une NOUVELLE QUESTION.
       Il faut décider à quel point se trouve le début de crue !! <=
- propager les dernières modifs de CV (une variable passée de _qpm à _qph)... DB, doc,..
- faire les checks de la section 5
- clarifier et confirmer une fois pour toute tous les usages d'indices en dur:
  - souvent un +1 ou -1 vient du fait a) soit qu'on ne veut pas le point courant; b) soit
    que tous les stacks n'ont pas le meme nombre d'éléments
  - le yoyo du "+3" doit à mon avis se conclure par la décision de Cécile: l'enlever pour
    de bon. Dans ce cas, le test passe de 
        if($ndata > $n_recent_to_consider+3){
    à
        if($ndata > $n_recent_to_consider){
    et est inutile, on est déjà dans un bloc qui a vérifié cette condition.
    Long story short: l'indice utilisé ensuite n'est pas en erreur car le vecteur stack
    est assez haut: $dq_local_vals[$n_recent_to_consider] -- c'est le point courant !
    Je pense que j'avais rajouté ce +3 pour être sur que dq_local était défini quand je
    testais $new_spate - c'est clair qu'il devait y avoir des fautes dans mon code, sorry.
    On peut donc remplacer, en commençant à la ligne 877:
            if($ndata > $n_recent_to_consider){             #BUG-R# (took off the "+3" on 160417 that was in there)  ### MUST CHECK ###
                # $dq_local = 1000.*($dq_local_vals[$n_recent_to_consider]-$dq_local_vals[0]);  ### 1000 multipliers was to get mm, removed 160417  ### MUST CHECK ###
                $dq_local = ($dq_local_vals[$n_recent_to_consider]-$dq_local_vals[0]);
            }
    par:
            $dq_local = ($dq_local_vals[$n_recent_to_consider]-$dq_local_vals[0]);
    puis relaxer, et move-on :-)
  - si jamais, en case de doute, on peut toujours afficher à STDOUT la taille d'un vecteur
    avec 'print "dernier indice de vecname = $#vecname\n";'. P.ex. à la ligne 881:
                # print "highest index in dq_local_vals = $#dq_local_vals\n"; # says 3 when $n_spate_thres_up=4
    cadire: la taille du vecteur devrait etre de 4 et le dernier indice est 3 -- all good !
développement pur:
- quel algo est le meilleur ? Différent pour T et Q ? paramètres de DB suffisants ?
- algo de pic assez raffiné ? moyenner sur des points voisins (via nouveau param DB) ? idem creux ?
- coder tout ça
    