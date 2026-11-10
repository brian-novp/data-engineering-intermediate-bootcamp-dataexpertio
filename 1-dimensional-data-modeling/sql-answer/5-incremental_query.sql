
insert into actors_history_scd
    select
        a.actorid,
        a.quality_class,
        a.is_active,
        
        a.current_year as start_date,
        
        9999 as end_date,
        
        true as is_current
    from actors a
    left join actors_history_scd scd
        on a.actorid = scd.actorid
        and scd.is_current = true 
    where
        
        (scd.actorid is null) 
        or (scd.quality_class <> a.quality_class 
            or scd.is_active <> a.is_active); 


-
update actors_history_scd
    set end_date = a.current_year - 1, 
        is_current = false 
    from actors a
    where actors_history_scd.actorid = a.actorid
        and actors_history_scd.is_current = true 
        and (actors_history_scd.quality_class <> a.quality_class
             or actors_history_scd.is_active <> a.is_active);