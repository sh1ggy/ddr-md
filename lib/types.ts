export interface Pokemon {
  name: string;
  sprites: {
    front_default: string;
  }
   types
   
   : [
    {
      "slot": 1,
      "type": [Object
      ]
    }
  ],
}

export interface Type {
  slot: number;
  type: {
    name: string;
    url: string;
  }
}
